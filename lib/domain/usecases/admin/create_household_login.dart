import '../../../core/errors/app_failure.dart';
import '../../../core/result/result.dart';
import '../../entities/household_login.dart';
import '../../repositories/auth_repository.dart';
import '../../value_objects/temporary_password.dart';

/// MTR-04 — an Area President gives a household in their own service area a
/// sign-in.
///
/// The temporary password is made here, never typed, and comes back once on
/// the result to be handed over. GEN-04 makes the household replace it at
/// first sign-in — the same path a new staff account takes.
///
/// The server decides whether this Area President may give this household a
/// sign-in, and whether the username is free. The check here is only the one
/// worth making before a round trip.
final class CreateHouseholdLogin {
  final AuthRepository auth;
  final TemporaryPasswordFactory newTemporaryPassword;

  const CreateHouseholdLogin({
    required this.auth,
    required this.newTemporaryPassword,
  });

  /// Offline nothing is created, and nothing is kept to try later.
  static const String needsSignal =
      'Giving a household a sign-in needs signal. Nothing was created. Try '
      "again when you're back online.";

  /// What is wrong with [username] as typed, or null when it is well formed.
  /// Whether it is free only the server can say.
  static ValidationFailure? checkUsername(String username) {
    if (!RegExp(
      r'^[a-z][a-z0-9._-]{2,49}$',
    ).hasMatch(username.trim().toLowerCase())) {
      return const ValidationFailure(
        'Use 3 to 50 lowercase letters, numbers, dots, underscores or '
        'hyphens. The username must start with a letter.',
      );
    }
    return null;
  }

  Future<Result<CreatedHouseholdLogin>> call({
    required HouseholdWithoutLogin household,
    required String username,
  }) async {
    final ValidationFailure? invalid = checkUsername(username);
    if (invalid != null) return Err<CreatedHouseholdLogin>(invalid);

    return (await auth.createHouseholdLogin(
      household: household,
      username: username.trim().toLowerCase(),
      temporaryPassword: newTemporaryPassword(),
    )).ifOffline(needsSignal);
  }
}
