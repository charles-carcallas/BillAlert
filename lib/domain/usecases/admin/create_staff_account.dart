import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/staff_account.dart';
import '../../repositories/auth_repository.dart';
import '../../value_objects/temporary_password.dart';

/// FR-31 — provisions a Meter Reader or Cashier in the Admin's own area.
///
/// The repository implementation calls a server-owned operation. No
/// service-role credential or synthetic email address crosses this layer.
///
/// The temporary password is made here, never typed, and comes back once on
/// the created account to be handed over.
final class CreateStaffAccount {
  final AuthRepository auth;
  final TemporaryPasswordFactory newTemporaryPassword;

  const CreateStaffAccount({
    required this.auth,
    required this.newTemporaryPassword,
  });

  /// Offline nothing is created, and nothing is kept to try later.
  static const String needsSignal =
      'Creating a staff account needs signal. Nothing was created. Try again '
      "when you're back online.";

  Future<Result<CreatedStaffAccount>> call({
    required String username,
    required String firstName,
    required String lastName,
    required String contactNumber,
    required StaffRole role,
  }) {
    final cleanUsername = username.trim().toLowerCase();
    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();

    if (!RegExp(r'^[a-z][a-z0-9._-]{2,49}$').hasMatch(cleanUsername)) {
      return Future<Result<CreatedStaffAccount>>.value(
        const Err<CreatedStaffAccount>(
          ValidationFailure(
            'Use 3 to 50 lowercase letters, numbers, dots, underscores or '
            'hyphens. The username must start with a letter.',
          ),
        ),
      );
    }
    if (cleanFirstName.isEmpty) {
      return Future<Result<CreatedStaffAccount>>.value(
        const Err<CreatedStaffAccount>(
          ValidationFailure('Enter the staff member\'s first name.'),
        ),
      );
    }
    if (cleanLastName.isEmpty) {
      return Future<Result<CreatedStaffAccount>>.value(
        const Err<CreatedStaffAccount>(
          ValidationFailure('Enter the staff member\'s last name.'),
        ),
      );
    }

    return auth
        .createStaffAccount(
          username: cleanUsername,
          firstName: cleanFirstName,
          lastName: cleanLastName,
          contactNumber: contactNumber.trim().isEmpty ? null : contactNumber,
          role: role,
          temporaryPassword: newTemporaryPassword(),
        )
        .then((result) => result.ifOffline(needsSignal));
  }
}
