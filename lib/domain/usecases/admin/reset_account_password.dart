import '../../../core/result/result.dart';
import '../../entities/managed_account.dart';
import '../../repositories/auth_repository.dart';
import '../../value_objects/temporary_password.dart';

/// An Area President resets a forgotten password in their own service area.
///
/// Nobody is handed a password they keep. They get a temporary one, made here
/// rather than typed, and GEN-04 makes them replace it at their next sign-in —
/// the same path a brand-new account takes — so the Area President never
/// knows the password that stays.
///
/// The server decides whether this Area President may reset this account.
final class ResetAccountPassword {
  final AuthRepository auth;
  final TemporaryPasswordFactory newTemporaryPassword;

  const ResetAccountPassword({
    required this.auth,
    required this.newTemporaryPassword,
  });

  /// The new temporary password, to be handed over once, when the reset
  /// succeeds.
  Future<Result<String>> call({required ManagedAccount account}) async {
    final String temporaryPassword = newTemporaryPassword();

    final result = await auth.resetAccountPassword(
      account: account,
      temporaryPassword: temporaryPassword,
    );

    return switch (result) {
      Ok() => Ok<String>(temporaryPassword),
      Err(:final failure) => Err<String>(failure),
    };
  }
}
