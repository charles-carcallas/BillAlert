import '../../core/result/result.dart';
import '../entities/app_user.dart';

/// Signing in, signing out, and knowing who is signed in.
///
/// The interface speaks in usernames because that is what the login screen
/// shows. Supabase Auth signs in with an email, so the implementation in
/// `data/` turns "ledesman.dormal" into the synthetic email the account was
/// created with. Presentation never learns that this happens.
abstract class AuthRepository {
  /// GEN-04. Returns the signed-in user, including whether they still have
  /// to change a temporary password.
  Future<Result<AppUser>> signIn({
    required String username,
    required String password,
  });

  /// GEN-06. Also wipes the encrypted cache, because the next person to sign
  /// in on this phone must not see the previous user's roster.
  Future<Result<void>> signOut();

  /// The user whose session was restored at startup, or null.
  Future<Result<AppUser?>> currentUser();

  /// Emits when the session changes, so the router can react to a sign-out
  /// or an expired token without every screen polling.
  Stream<AppUser?> authChanges();

  /// GEN-04: replaces a temporary password and clears must_change_password.
  Future<Result<void>> changePassword({required String newPassword});
}
