import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../providers.dart';

/// Whether a signed-in session is waiting for the phone's screen lock.
final class AppLockState {
  /// A session was restored on a phone where fingerprint sign-in is on, and
  /// nobody has confirmed it yet. The router holds the app on the sign-in
  /// screen until this is false.
  final bool locked;

  /// Somebody has just signed in with a password on a phone that could
  /// unlock with a fingerprint instead, and has not been asked yet.
  final bool offerFingerprint;

  const AppLockState({this.locked = false, this.offerFingerprint = false});
}

/// Fingerprint sign-in: when to lock, and what lifts it.
///
/// The Supabase session already survives the app being closed, so reopening
/// BillAlert has always gone straight to the home screen. This does not
/// change what is stored. It decides whether that restored session may be
/// used before the phone's own lock has confirmed who is holding it.
///
/// [build] never touches the fingerprint sensor or storage. Every screen
/// test that draws the sign-in screen or the tab shell builds this, and none
/// of them has a phone behind it.
class AppLockController extends Notifier<AppLockState> {
  @override
  AppLockState build() => const AppLockState();

  /// Start-up, with the user whose session was restored.
  Future<void> lockIfTurnedOnFor(AppUser user) async {
    if (!await ref.read(fingerprintSettingProvider).isOnFor(user.id)) return;

    // The setting may outlive the phone's screen lock. Locking a phone that
    // can no longer show the prompt would leave nothing to press but "Sign
    // in with a different account", so it opens as it did before instead.
    if (!await ref.read(deviceUnlockProvider).isAvailable()) return;

    state = const AppLockState(locked: true);
  }

  /// After a successful password sign-in. A password is proof enough, so
  /// nothing stays locked; and a person not yet asked about fingerprint
  /// sign-in, on a phone that can do it, is asked once.
  Future<void> afterPasswordSignIn(AppUser user) async {
    state = const AppLockState();

    final setting = ref.read(fingerprintSettingProvider);
    if (await setting.isOnFor(user.id)) return;
    if (await setting.wasOfferedTo(user.id)) return;
    if (!await ref.read(deviceUnlockProvider).isAvailable()) return;

    state = const AppLockState(offerFingerprint: true);
  }

  /// The "Unlock with fingerprint" button. Returns null on success.
  Future<AppFailure?> unlock() async {
    final result = await ref
        .read(deviceUnlockProvider)
        .confirmIdentity(reason: 'Confirm it’s you to open BillAlert');

    switch (result) {
      case Ok():
        state = const AppLockState();
        return null;
      case Err(:final failure):
        return failure;
    }
  }

  /// Offline password tries allowed before the lock insists on the
  /// fingerprint or on signal. The server rate-limits online tries itself.
  static const int maxOfflinePasswordTries = 5;

  int _offlinePasswordTries = 0;

  /// "Use username and password" on the lock, for the SAME account.
  ///
  /// This used to sign the session out and show the ordinary form, which
  /// with no signal left nobody able to get back in: signing out destroys the
  /// session and the phone's saved data, and a fresh sign-in needs the server.
  /// Now the session stays. With signal the server checks the password; with
  /// none, it is checked against the last password the server accepted on
  /// this phone. Returns null when the lock lifts.
  Future<AppFailure?> unlockWithPassword(AppUser user, String password) async {
    if (password.isEmpty) {
      return const ValidationFailure('Enter your password.');
    }

    final result = await ref.read(signInProvider)(
      username: user.username,
      password: password,
    );

    switch (result) {
      case Ok():
        _offlinePasswordTries = 0;
        await ref.read(passwordVerifierProvider).remember(user.id, password);
        state = const AppLockState();
        return null;
      case Err(:final failure) when failure is! NetworkFailure:
        return failure;
      case Err():
        break;
    }

    // No signal: check against this phone's copy of the server's last yes.
    if (_offlinePasswordTries >= maxOfflinePasswordTries) {
      return const AuthFailure(
        'Too many tries without signal. Use your fingerprint, or connect to '
        'the internet and try again.',
      );
    }
    final bool? matches = await ref
        .read(passwordVerifierProvider)
        .matches(user.id, password);
    switch (matches) {
      case true:
        _offlinePasswordTries = 0;
        state = const AppLockState();
        return null;
      case false:
        _offlinePasswordTries++;
        return const AuthFailure(
          'That password is incorrect. You are offline, so it was checked on '
          'this phone.',
        );
      case null:
        return const NetworkFailure(
          'No connection, and this phone has not saved a password check for '
          'your account yet. Use your fingerprint, or connect to the internet '
          'and try again.',
        );
    }
  }

  /// "Use fingerprint" in the offer.
  ///
  /// Confirms once before saving anything. That proves the sensor or PIN
  /// works on this phone before the app starts depending on it, and it means
  /// whoever turns the lock on is holding the phone the person just signed
  /// in on.
  Future<AppFailure?> turnOnFor(AppUser user) async {
    final result = await ref
        .read(deviceUnlockProvider)
        .confirmIdentity(
          reason: 'Confirm it’s you to turn on fingerprint sign-in',
        );

    if (result case Err(:final failure)) return failure;

    try {
      final setting = ref.read(fingerprintSettingProvider);
      await setting.turnOnFor(user.id);
      await setting.markOfferedTo(user.id);
    } catch (error) {
      return ValidationFailure(
        'Fingerprint sign-in could not be saved on this phone. Try again.',
        '$error',
      );
    }

    state = const AppLockState();
    return null;
  }

  /// "Not now" in the offer. Remembered, so it is not asked again.
  Future<void> declineOffer(AppUser user) async {
    state = const AppLockState();
    try {
      await ref.read(fingerprintSettingProvider).markOfferedTo(user.id);
    } catch (_) {
      // Not saving a "no" only means being asked again next sign-in.
    }
  }

  /// The Profile switch, turned off. Returns null on success.
  ///
  /// Confirms first, like turning it on. Turning it off removes the lock from
  /// every future start of the app, and whoever is holding a phone that is
  /// already open must not be able to do that without the phone's say-so.
  Future<AppFailure?> turnOff() async {
    final result = await ref
        .read(deviceUnlockProvider)
        .confirmIdentity(
          reason: 'Confirm it’s you to turn off fingerprint sign-in',
        );

    if (result case Err(:final failure)) return failure;

    try {
      await ref.read(fingerprintSettingProvider).turnOff();
    } catch (error) {
      return ValidationFailure(
        'Fingerprint sign-in could not be turned off on this phone. Try again.',
        '$error',
      );
    }
    return null;
  }

  /// Signing out, or a session that ended. Nothing locked, nothing offered.
  /// The setting itself stays, so the next password sign-in on this phone
  /// keeps using it.
  void reset() => state = const AppLockState();
}

final appLockControllerProvider =
    NotifierProvider<AppLockController, AppLockState>(AppLockController.new);
