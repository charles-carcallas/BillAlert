import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/managed_account.dart';
import '../../repositories/auth_repository.dart';

/// An Area President resets a forgotten password in their own service area.
///
/// Nobody is handed a password they keep. They get a temporary one, and
/// GEN-04 makes them replace it at their next sign-in — the same path a
/// brand-new account takes — so the Area President never knows the password
/// that stays.
///
/// The server decides whether this Area President may reset this account.
/// The checks here are only the ones worth making before a round trip.
final class ResetAccountPassword {
  static const int minimumLength = 8;

  final AuthRepository auth;

  const ResetAccountPassword({required this.auth});

  Future<Result<void>> call({
    required ManagedAccount account,
    required String temporaryPassword,
    required String confirmPassword,
  }) async {
    if (temporaryPassword.length < minimumLength) {
      return const Err<void>(
        ValidationFailure(
          'The temporary password must be at least $minimumLength characters.',
        ),
      );
    }
    if (temporaryPassword != confirmPassword) {
      return const Err<void>(
        ValidationFailure('The temporary passwords do not match.'),
      );
    }

    return auth.resetAccountPassword(
      account: account,
      temporaryPassword: temporaryPassword,
    );
  }
}
