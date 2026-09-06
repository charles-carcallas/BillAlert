import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/app_user.dart';
import '../../repositories/auth_repository.dart';

/// GEN-01 - somebody signs in.
///
/// The username is what the login screen shows ("ledesman.dormal"). Turning
/// it into the credential Supabase Auth expects is the repository job, not
/// this one, and not the screen one.
final class SignIn {
  final AuthRepository auth;

  const SignIn({required this.auth});

  Future<Result<AppUser>> call({
    required String username,
    required String password,
  }) async {
    if (username.trim().isEmpty) {
      return const Err(ValidationFailure('Please enter your username.'));
    }
    if (password.isEmpty) {
      return const Err(ValidationFailure('Please enter your password.'));
    }
    return auth.signIn(username: username.trim(), password: password);
  }
}
