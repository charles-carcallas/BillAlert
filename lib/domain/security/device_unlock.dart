import '../../core/result/result.dart';

/// Confirms, with the phone's own screen lock, that the person holding the
/// phone is the person who signed in on it.
///
/// Phase 1: a user "shall be able to log back into the application using the
/// device biometric or the device passcode, instead of entering the password
/// again". The fingerprint, face or PIN is checked by the operating system.
/// BillAlert only ever learns yes or no — never the fingerprint itself.
///
/// An interface for the same reason [PhClock] is one: the rules about when
/// to lock and when to let somebody through are worth testing, and a test
/// cannot press a fingerprint sensor.
abstract class DeviceUnlock {
  /// Whether this phone can confirm identity at all: a fingerprint or face
  /// sensor, or at least a screen-lock PIN, pattern or password. False on
  /// the web build, which has no screen lock to ask.
  Future<bool> isAvailable();

  /// Shows the system prompt with [reason] as its message.
  ///
  /// Ok when the person confirmed. Err with a plain-English failure when they
  /// cancelled, the phone has locked the sensor after too many attempts, or
  /// there is no screen lock set up.
  Future<Result<void>> confirmIdentity({required String reason});
}
