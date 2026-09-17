import '../value_objects/ids.dart';

/// Lets a locked session be opened with the account's password when there is
/// no signal to check it with the server.
///
/// The password itself is never kept. What is kept is a salted, slow hash of
/// the last password that the SERVER accepted for this profile on this phone,
/// so the offline check can only ever agree with an answer the server already
/// gave. It unlocks the session already on the phone; it never signs anybody
/// in who was not signed in.
abstract class PasswordVerifier {
  /// After the server accepted [password] for [profile].
  Future<void> remember(ProfileId profile, String password);

  /// True or false when a hash is kept for [profile]; null when this phone
  /// has never seen the server accept a password for it.
  Future<bool?> matches(ProfileId profile, String password);

  /// On sign-out, so nothing about the account is left on the phone.
  Future<void> forget(ProfileId profile);
}
