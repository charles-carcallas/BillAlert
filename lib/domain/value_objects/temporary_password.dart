import 'dart:math';

/// Makes a temporary password. Injected, like [ClientUuidFactory], so a test
/// can hand out a known one.
typedef TemporaryPasswordFactory = String Function();

/// The temporary password an Area President hands over: "BillAlert4829".
///
/// Nobody types it. When a person picks one, they pick "12345678", or the
/// same one for everyone, and then knowing a username is enough to sign in as
/// that person before they do.
///
/// The word is what makes it easy to read out or write on a slip. The four
/// random digits are what stop someone who knows the pattern from signing in
/// as someone else. Four is a deliberate trade-off: 10,000 possibilities is
/// short enough to say aloud, and enough for a password that only has to last
/// until its owner's first sign-in — which then demands a new one (GEN-04) —
/// against a server that slows down repeated sign-in attempts.
final class TemporaryPassword {
  const TemporaryPassword._();

  static const String prefix = 'BillAlert';

  /// A new one, from a cryptographically secure source unless a test passes
  /// its own.
  static String generate([Random? random]) {
    final Random source = random ?? Random.secure();
    return '$prefix${source.nextInt(10000).toString().padLeft(4, '0')}';
  }
}
