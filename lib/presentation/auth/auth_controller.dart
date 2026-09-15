import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../providers.dart';
import 'app_lock_controller.dart';

/// Who is signed in, for the whole app.
///
/// The router watches this and sends each role to its own home, so this is
/// the only place that knows about the session. Screens call [signIn] and
/// [signOut] and read the failure message; they never touch a repository and
/// they certainly never touch Supabase.
class AuthController extends AsyncNotifier<AppUser?> {
  /// Guards against the auth stream firing before the first build has
  /// finished, which would be an assignment to `state` that Riverpod rejects.
  bool _ready = false;

  @override
  Future<AppUser?> build() async {
    final repository = ref.watch(authRepositoryProvider);

    // Reacts to a sign-out or an expired token from anywhere, so the router
    // moves without every screen having to poll.
    final subscription = repository.authChanges().listen((AppUser? user) {
      if (_ready) {
        // A session that has ended cannot still be waiting to be unlocked.
        if (user == null) ref.read(appLockControllerProvider.notifier).reset();
        state = AsyncData<AppUser?>(user);
      }
    });
    ref.onDispose(subscription.cancel);

    final restored = await repository.currentUser();

    final AppUser? user = switch (restored) {
      Ok(:final value) => value,
      // A failure restoring a session is not something to show on a splash
      // screen. Treat it as "not signed in" and let them sign in again.
      Err() => null,
    };

    // Fingerprint sign-in: settle whether this restored session is locked
    // BEFORE the user is handed to the router, and before the auth stream is
    // allowed to publish one. Otherwise the router sees a signed-in, unlocked
    // user for a moment, draws their home screen, and only then snaps back to
    // the lock — showing the very contents the lock exists to protect.
    if (user != null) {
      await ref
          .read(appLockControllerProvider.notifier)
          .lockIfTurnedOnFor(user);

      // A restored session needs the same reconnect listener as a fresh
      // password sign-in. Without this, force-killing the app while offline
      // and reopening it left the durable outbox stranded even after signal
      // returned.
      final sync = ref.read(syncServiceProvider);
      sync.start();
      unawaited(sync.syncNow());
    }
    _ready = true;

    return user;
  }

  /// Returns null on success, or the failure to show under the form.
  Future<AppFailure?> signIn({
    required String username,
    required String password,
  }) async {
    // Deliberately NOT `state = AsyncLoading()`.
    //
    // This state means "who is signed in", and the router watches it. Setting
    // it to loading mid-attempt made the redirect think the app was still
    // restoring a session, so it pushed the user to the splash screen, threw
    // the LoginScreen away, and came back to a fresh one — discarding the
    // failure message this method had just returned. The symptom was a login
    // form that blinked and cleared instead of saying what went wrong.
    //
    // The spinner is the screen's own business; LoginScreen tracks it with
    // `_isSubmitting`.
    final result = await ref.read(signInProvider)(
      username: username,
      password: password,
    );

    switch (result) {
      case Ok(:final value):
        _ready = true;
        // A password is proof enough, so nothing stays locked — and this is
        // where the phone decides whether to offer fingerprint sign-in. It is
        // settled before the user is published, so the home screen the
        // router opens already knows whether to ask.
        await ref
            .read(appLockControllerProvider.notifier)
            .afterPasswordSignIn(value);
        state = AsyncData<AppUser?>(value);
        // MTR-11/12: start draining anything left in the outbox from the last
        // session as soon as somebody is signed in again.
        ref.read(syncServiceProvider).start();
        unawaited(ref.read(syncServiceProvider).syncNow());
        return null;

      case Err(:final failure):
        state = const AsyncData<AppUser?>(null);
        return failure;
    }
  }

  Future<AppFailure?> signOut() async {
    final result = await ref.read(signOutProvider)();
    await ref.read(syncServiceProvider).stop();
    // GEN-06 reaches the notification tray too. The next person to sign in on
    // this phone must not be reminded about the last household's bills, nor
    // see its notices.
    await ref.read(backgroundAlertsProvider).stop();
    await ref.read(phoneNotifierProvider).cancelAll();
    ref.read(appLockControllerProvider.notifier).reset();
    state = const AsyncData<AppUser?>(null);

    return switch (result) {
      Ok() => null,
      Err(:final failure) => failure,
    };
  }

  /// GEN-04: after the temporary password is replaced, the flag comes down
  /// and the router lets the user through to their own home screen.
  Future<AppFailure?> changePassword({
    required String newPassword,
    required String confirmPassword,
  }) async {
    final result = await ref.read(changePasswordProvider)(
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );

    switch (result) {
      case Err(:final failure):
        return failure;
      case Ok():
        final refreshed = await ref.read(authRepositoryProvider).currentUser();
        if (refreshed case Ok(:final value)) {
          state = AsyncData<AppUser?>(value);
        }
        return null;
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);
