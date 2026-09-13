import '../value_objects/ids.dart';

/// Whether fingerprint sign-in is turned on for this phone, and for whom.
///
/// Kept per profile. Two staff can share one phone, and turning it on for one
/// of them must not let the other through with their fingerprint — nor lock
/// the other out behind a prompt they never asked for.
abstract class FingerprintSetting {
  Future<bool> isOnFor(ProfileId profile);

  Future<void> turnOnFor(ProfileId profile);

  Future<void> turnOff();

  /// Whether this person has already been asked. The offer after a password
  /// sign-in is made once: "Not now" must not become a question at every
  /// sign-in.
  Future<bool> wasOfferedTo(ProfileId profile);

  Future<void> markOfferedTo(ProfileId profile);
}
