import '../value_objects/ids.dart';

/// MTR-04: an active household in the Area President's own service area
/// that has no sign-in yet.
///
/// Staff can bill it, read its meter and take its payments, but the
/// household itself cannot open BillAlert until it is given a sign-in.
final class HouseholdWithoutLogin {
  final ConsumerId id;
  final ConsumerNumber consumerNo;
  final String firstName;
  final String lastName;
  final String? purok;

  const HouseholdWithoutLogin({
    required this.id,
    required this.consumerNo,
    required this.firstName,
    required this.lastName,
    this.purok,
  });

  String get fullName => '$firstName $lastName';

  /// Whether a search box's [query] finds this household, by name or by
  /// consumer number.
  bool matches(String query) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q) ||
        consumerNo.value.toLowerCase().contains(q);
  }

  /// The username [usernameFor] suggests for this household's name.
  String get suggestedUsername => usernameFor(firstName, lastName);

  /// "Lorna Caberte" becomes "lorna.caberte", the same shape every existing
  /// sign-in has. Only a suggestion: the Area President can change it, and
  /// the server decides whether it is free.
  ///
  /// Empty when the name cannot make a valid username, so the field starts
  /// blank rather than holding something the server will refuse.
  static String usernameFor(String firstName, String lastName) {
    String part(String name) => name
        .toLowerCase()
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[^a-z0-9.]'), '');

    final String joined = '${part(firstName)}.${part(lastName)}'
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'^\.+|\.+$'), '');

    return RegExp(r'^[a-z][a-z0-9._-]{2,49}$').hasMatch(joined) ? joined : '';
  }
}

/// What comes back once a household has been given a sign-in.
final class CreatedHouseholdLogin {
  final ProfileId id;
  final String username;
  final HouseholdWithoutLogin household;

  /// Shown once, on the confirmation, to be handed over. Never stored: the
  /// household must replace it at first sign-in.
  final String temporaryPassword;

  const CreatedHouseholdLogin({
    required this.id,
    required this.username,
    required this.household,
    required this.temporaryPassword,
  });
}
