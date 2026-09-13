import '../value_objects/ids.dart';

/// The kinds of sign-in an Area President looks after.
///
/// There is no Area President here on purpose. One Area President must not
/// be able to reset another's password: that would be a way to take over
/// their account and their area.
enum ManagedAccountKind {
  meterReader('Meter Reader'),
  cashier('Cashier'),
  consumer('Consumer');

  final String label;

  const ManagedAccountKind(this.label);
}

/// A sign-in in the Area President's own service area whose password they
/// may reset.
final class ManagedAccount {
  final ProfileId id;
  final String firstName;
  final String lastName;
  final ManagedAccountKind kind;

  /// The username for staff; the consumer number for a household, because
  /// that is what is printed on the bill and what they quote at the counter.
  final String reference;

  const ManagedAccount({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.kind,
    required this.reference,
  });

  String get fullName => '$firstName $lastName';

  /// Whether a search box's [query] finds this account, by name or by
  /// username or consumer number.
  bool matches(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        reference.toLowerCase().contains(q);
  }
}
