import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../repositories/auth_repository.dart';

/// GEN-04 - a new account is issued a temporary password and must replace it
/// before it can reach anything else.
///
/// The router enforces the "anything else" part: a user whose
/// mustChangePassword flag is set can only reach this screen.
final class ChangePassword {
  final AuthRepository auth;

  static const int minimumLength = 8;

  const ChangePassword({required this.auth});

  Future<Result<void>> call({
    required String newPassword,
    required String confirmPassword,
  }) async {
    if (newPassword.length < minimumLength) {
      return const Err(ValidationFailure(
        'Your new password must be at least $minimumLength characters long.',
      ));
    }
    if (newPassword != confirmPassword) {
      return const Err(ValidationFailure(
        'The two passwords do not match. Please type them again.',
      ));
    }
    return auth.changePassword(newPassword: newPassword);
  }
}
