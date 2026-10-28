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

  /// True while this person's own sign-out runs, so it is not mistaken for
  /// the server ending the session.
  bool _signingOut = false;
  int _generation = 0;
  bool _confirming = false;

  @override
  Future<AppUser?> build() async {
    final repository = ref.watch(authRepositoryProvider);

    // Reacts to a sign-out or an expired token from anywhere, so the router
    // moves without every screen having to poll.
    final subscription = repository.authChanges().listen((AppUser? user) {
      if (_ready && !_signingOut) {
        if (user == null) {
          ref.read(outboxSessionProvider).bind(null);
          unawaited(ref.read(syncServiceProvider).stop());
          if (!_signingOut) {
            unawaited(ref.read(backgroundAlertsProvider).stop());
            unawaited(ref.read(phoneNotifierProvider).cancelAll());
          }
          // A session that has ended cannot still be waiting to be unlocked.
          ref.read(appLockControllerProvider.notifier).reset();
          // Signed out without asking to be: the session was ended somewhere
          // else, most often by a password reset. Say so on the sign-in
          // screen instead of dropping them there with no reason.
          if (!_signingOut && state.value != null) {
            ref.read(signInNoticeProvider.notifier).show(_signedOutByReset);
          }
        }
        final session = ref.read(outboxSessionProvider);
        final scope = session.scope;
        if (user != null &&
            scope != null &&
            (scope.id != user.id.value ||
                scope.role != user.roleCode ||
                scope.area != user.areaId?.value ||
                state.value?.accessVersion != user.accessVersion)) {
          session.bind(null);
          final sync = ref.read(syncServiceProvider);
          unawaited(
            sync.stop().then((_) {
              if (!ref.mounted ||
                  state.value?.id != user.id ||
                  state.value?.roleCode != user.roleCode ||
                  state.value?.areaId != user.areaId) {
                return;
              }
              session.bind(user);
              sync.start();
              unawaited(sync.syncNow());
            }),
          );
        }
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
      ref.read(outboxSessionProvider).bind(user);
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
    final generation = ++_generation;
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
    await ref.read(syncServiceProvider).stop();
    ref.read(outboxSessionProvider).bind(null);
    final result = await ref.read(signInProvider)(
      username: username,
      password: password,
    );
    if (!ref.mounted || generation != _generation) return const AuthFailure();

    switch (result) {
      case Ok(:final value):
        if (!ref.mounted || generation != _generation) {
          return const AuthFailure();
        }
        _ready = true;
        // The server just accepted this password, so this phone may check it
        // again later when the lock is opened without signal.
        await ref.read(passwordVerifierProvider).remember(value.id, password);
        // A password is proof enough, so nothing stays locked — and this is
        // where the phone decides whether to offer fingerprint sign-in. It is
        // settled before the user is published, so the home screen the
        // router opens already knows whether to ask.
        await ref
            .read(appLockControllerProvider.notifier)
            .afterPasswordSignIn(value);
        if (!ref.mounted || generation != _generation) {
          return const AuthFailure();
        }
        ref.read(outboxSessionProvider).bind(value);
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
    _generation++;
    _signingOut = true;
    try {
      final AppUser? leaving = state.value;
      state = const AsyncData<AppUser?>(null);
      await ref.read(syncServiceProvider).stop();
      ref.read(outboxSessionProvider).bind(null);
      final result = await ref.read(signOutProvider)();
      if (leaving != null) {
        await ref.read(passwordVerifierProvider).forget(leaving.id);
      }
      await ref.read(syncServiceProvider).stop();
      // GEN-06 reaches the notification tray too. The next person to sign in
      // on this phone must not be reminded about the last household's bills,
      // nor see its notices.
      await ref.read(backgroundAlertsProvider).stop();
      await ref.read(phoneNotifierProvider).cancelAll();
      ref.read(appLockControllerProvider.notifier).reset();
      state = const AsyncData<AppUser?>(null);

      return switch (result) {
        Ok() => null,
        Err(:final failure) => failure,
      };
    } finally {
      _signingOut = false;
    }
  }

  /// Signs out a phone whose session was ended on the server, as soon as the
  /// phone can ask. A password reset ends every session of the account, but a
  /// phone still holding a short-lived token could otherwise keep showing that
  /// account for up to an hour.
  ///
  /// Without signal nothing happens: the phone keeps working from what it has
  /// saved and asks again next time.
  Future<void> confirmSession() async {
    if (state.value == null || _confirming || _signingOut) return;
    _confirming = true;
    final generation = _generation;
    final previous = state.value!;
    try {
      final Result<void> result;
      try {
        result = await ref.read(authRepositoryProvider).confirmSession();
      } catch (_) {
        return;
      }
      if (!ref.mounted ||
          generation != _generation ||
          state.value?.id != previous.id) {
        return;
      }
      if (result case Err(:final failure) when failure is AuthFailure) {
        if (state.value == null) return;
        ref
            .read(signInNoticeProvider.notifier)
            .show(
              failure.message == AuthFailure.disabledMessage
                  ? AuthFailure.disabledMessage
                  : _signedOutByReset,
            );
        await signOut();
        return;
      }
      if (result is Err<void>) return;
      final refreshed = await ref.read(authRepositoryProvider).currentUser();
      if (!ref.mounted ||
          generation != _generation ||
          state.value?.id != previous.id) {
        return;
      }
      if (refreshed case Ok(:final value)) {
        if (value == null) {
          await signOut();
          return;
        }
        if (previous.accessScope != value.accessScope) {
          ref.read(outboxSessionProvider).bind(null);
          await ref.read(syncServiceProvider).stop();
          await ref.read(phoneNotifierProvider).cancelAll();
          if (!ref.mounted || generation != _generation) return;
          ref.read(outboxSessionProvider).bind(value);
          ref.read(syncServiceProvider).start();
        }
        state = AsyncData<AppUser?>(value);
      } else if (refreshed case Err(failure: AuthFailure())) {
        await signOut();
      }
    } finally {
      _confirming = false;
    }
  }

  /// GEN-04: after the temporary password is replaced, the flag comes down
  /// and the router lets the user through to their own home screen.
  Future<AppFailure?> changePassword({
    required String newPassword,
    required String confirmPassword,
  }) async {
    final generation = _generation;
    final result = await ref.read(changePasswordProvider)(
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );
    if (!ref.mounted || generation != _generation) return const AuthFailure();

    switch (result) {
      case Err(:final failure):
        if (failure is AuthFailure) {
          // The session this screen opened with has ended on the server. An
          // Area President resetting the password does exactly that: Supabase
          // Auth ends every session of the account the moment a password is
          // set for it. The phone can still read with its short-lived access
          // token, which is how the change-password screen opened at all, but
          // nothing that goes through Auth will work again. Staying on a
          // screen that cannot be left or completed is a dead end, so sign
          // out, and tell the sign-in screen why.
          ref.read(signInNoticeProvider.notifier).show(_signedOutByReset);
          await signOut();
        }
        return failure;
      case Ok():
        final refreshed = await ref.read(authRepositoryProvider).currentUser();
        if (!ref.mounted || generation != _generation) {
          return const AuthFailure();
        }
        if (refreshed case Ok(:final value)) {
          if (value != null) {
            // The old password must stop opening the lock offline.
            await ref
                .read(passwordVerifierProvider)
                .remember(value.id, newPassword);
          }
          if (!ref.mounted || generation != _generation) {
            return const AuthFailure();
          }
          state = AsyncData<AppUser?>(value);
        }
        return null;
    }
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(
  AuthController.new,
);

const String _signedOutByReset =
    'You were signed out on this phone, usually because your password was '
    'reset. Sign in with your current password, or the temporary one from '
    'your Area President.';

/// One sentence for the sign-in screen about why somebody is looking at it,
/// when the app sent them there rather than they chose to sign out. Cleared
/// by the next sign-in attempt.
class SignInNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}

final signInNoticeProvider = NotifierProvider<SignInNotice, String?>(
  SignInNotice.new,
);
