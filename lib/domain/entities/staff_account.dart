import '../value_objects/ids.dart';

/// A staff role an Area President is allowed to provision.
///
/// Admin is deliberately absent. An Area President cannot mint another Area
/// President from a client-facing operation, even inside their own area.
enum StaffRole {
  meterReader('meter_reader', 'Meter Reader'),
  cashier('cashier', 'Cashier');

  final String code;
  final String label;

  const StaffRole(this.code, this.label);
}

/// What comes back once a staff sign-in is provisioned.
final class CreatedStaffAccount {
  final ProfileId id;
  final String username;
  final String firstName;
  final String lastName;
  final StaffRole role;
  final String? contactNumber;

  /// Shown once, on the confirmation, to be handed over. Never stored: the
  /// staff member must replace it at first sign-in.
  final String temporaryPassword;

  const CreatedStaffAccount({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.role,
    required this.contactNumber,
    required this.temporaryPassword,
  });

  String get fullName => '$firstName $lastName';
}
