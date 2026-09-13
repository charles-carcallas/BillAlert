import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/security/device_unlock.dart';

/// The phone's screen lock, through `local_auth`.
///
/// Android draws its own prompt — fingerprint, face, or the phone's PIN,
/// pattern or password — and tells the app only whether it succeeded. The
/// fingerprint never reaches BillAlert, which is what lets the sign-in screen
/// promise that it never leaves the device.
///
/// Every failure becomes an [AuthFailure] with a sentence a meter reader can
/// act on. The plugin's own descriptions are written for developers
/// ("BiometricPrompt canceled by user") and are kept in `debugDetail`, never
/// shown.
class LocalAuthDeviceUnlock implements DeviceUnlock {
  final LocalAuthentication _auth;

  LocalAuthDeviceUnlock([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    // local_auth has no web implementation, and a browser has no screen lock
    // to ask. Checked first, so the demo build in Edge never calls into a
    // plugin that is not there.
    if (kIsWeb) return false;
    try {
      // True for a sensor OR a PIN, pattern or password. The prompt is not
      // restricted to biometrics, so either is enough.
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Result<void>> confirmIdentity({required String reason}) async {
    if (kIsWeb) return const Err<void>(AuthFailure(noScreenLock));

    try {
      final bool confirmed = await _auth.authenticate(
        localizedReason: reason,
        // Phase 1 promises "the device biometric OR the device passcode". A
        // wet finger or a cracked sensor still leaves the phone's PIN.
        biometricOnly: false,
      );
      return confirmed
          ? const Ok<void>(null)
          : const Err<void>(AuthFailure(cancelled));
    } on LocalAuthException catch (error) {
      return Err<void>(AuthFailure(_messageFor(error.code), '$error'));
    } catch (error) {
      return Err<void>(AuthFailure(couldNotCheck, '$error'));
    }
  }

  static const String cancelled =
      'Unlock was cancelled. Try again, or sign in with a different account.';

  static const String noScreenLock =
      'This phone has no screen lock set up. Add a fingerprint or PIN in the '
      "phone's settings, or sign in with a different account.";

  static const String couldNotCheck =
      "This phone couldn't check your fingerprint. Try again, or sign in with "
      'a different account.';

  static const String tooManyTries =
      'Too many attempts. Wait 30 seconds, then try again.';

  static const String sensorLocked =
      'Fingerprint is locked after too many attempts. Unlock the phone with its '
      'PIN first, then try again.';

  /// The plugin says new codes may be added in any release, so this always
  /// ends in a default rather than trying to name them all.
  static String _messageFor(LocalAuthExceptionCode code) => switch (code) {
    LocalAuthExceptionCode.userCanceled ||
    LocalAuthExceptionCode.systemCanceled ||
    LocalAuthExceptionCode.timeout ||
    LocalAuthExceptionCode.userRequestedFallback => cancelled,
    LocalAuthExceptionCode.noCredentialsSet => noScreenLock,
    LocalAuthExceptionCode.temporaryLockout => tooManyTries,
    LocalAuthExceptionCode.biometricLockout => sensorLocked,
    _ => couldNotCheck,
  };
}
