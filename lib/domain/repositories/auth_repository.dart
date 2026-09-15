import '../../core/result/result.dart';
import '../entities/app_user.dart';
import '../entities/household_login.dart';
import '../entities/managed_account.dart';
import '../entities/staff_account.dart';
import '../value_objects/ids.dart';

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

  /// FR-31: provisions a Meter Reader or Cashier in the signed-in Admin's
  /// area. The implementation delegates the privileged auth-user write to
  /// the server; it must never use a service-role key in this client.
  Future<Result<CreatedStaffAccount>> createStaffAccount({
    required String username,
    required String firstName,
    required String lastName,
    required String? contactNumber,
    required StaffRole role,
    required String temporaryPassword,
  });

  /// The sign-ins in [areaId] whose password the signed-in Area President
  /// may reset: that area's Meter Readers and Cashiers, and its households
  /// that have a login.
  Future<Result<List<ManagedAccount>>> managedAccounts(AreaId areaId);

  /// Gives [account] a temporary password and requires them to replace it at
  /// their next sign-in. Server-owned, like [createStaffAccount]: this client
  /// never holds the key that changes another person's password, and the
  /// server decides whether this Area President may reset this account.
  Future<Result<void>> resetAccountPassword({
    required ManagedAccount account,
    required String temporaryPassword,
  });

  /// MTR-04: the active households in [areaId] that cannot sign in yet.
  Future<Result<List<HouseholdWithoutLogin>>> householdsWithoutLogin(
    AreaId areaId,
  );

  /// MTR-04: gives [household] a sign-in with [username] and a temporary
  /// password it must replace at first sign-in. Server-owned, like
  /// [createStaffAccount]: the server checks the household is in this Area
  /// President's area and has no sign-in, and takes the name from its record.
  Future<Result<CreatedHouseholdLogin>> createHouseholdLogin({
    required HouseholdWithoutLogin household,
    required String username,
    required String temporaryPassword,
  });
}
