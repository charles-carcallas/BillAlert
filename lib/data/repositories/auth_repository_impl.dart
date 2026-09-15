import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/household_login.dart';
import '../../domain/entities/managed_account.dart';
import '../../domain/entities/staff_account.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../dto/profile_dto.dart';
import '../local/app_database.dart';
import '../supabase/failure_mapper.dart';

/// Sign-in against Supabase Auth, plus the `profiles` row that says who the
/// person actually is.
///
/// The login screen asks for a username because that is what the design
/// shows and what staff are given. Supabase Auth signs in with an email, so
/// the two are bridged here — "ledesman.dormal" becomes
/// "ledesman.dormal@billalert.local" — and nothing above this layer knows.
/// If the team later switches to signing in with a mobile number, this is the
/// only file that changes.
class AuthRepositoryImpl implements AuthRepository {
  final SupabaseClient _client;
  final AppDatabase _db;

  const AuthRepositoryImpl(this._client, this._db);

  /// Turns the username a person types into the email their account was
  /// created with: "ledesman.dormal" -> "ledesman.dormal@billalert.local".
  ///
  /// **This is the only mapping in the app.** It lives here, on the one class
  /// that talks to Supabase Auth, so that no screen, view model or use case
  /// can build an email address even by accident — they all deal in usernames,
  /// which is the only thing staff are ever given.
  ///
  /// The input is trimmed and lowercased first, because a username typed on a
  /// phone keyboard arrives as " Ledesman.Dormal " often enough that treating
  /// it as a different account would just look like the app is broken.
  ///
  /// It is `static` rather than private so the mapping can be unit-tested
  /// without constructing a SupabaseClient; see
  /// test/data/auth_email_mapping_test.dart.
  static String emailForUsername(String username) =>
      '${username.trim().toLowerCase()}@${AppConfig.loginEmailDomain}';

  @override
  Future<Result<AppUser>> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: emailForUsername(username),
        password: password,
      );

      final user = response.user;
      if (user == null) {
        // Same wording as the wrong-password case in FailureMapper. The user
        // never sees the synthetic email, so an error that mentioned one would
        // be describing something they have never been shown.
        return const Err<AppUser>(
          AuthFailure(
            'That username or password is not correct. Please try again.',
          ),
        );
      }

      final profileResult = await _loadProfile(user.id);
      switch (profileResult) {
        case Err(:final failure):
          return Err<AppUser>(failure);
        case Ok(:final value):
          if (value == null) {
            // Authenticated, but with no profile row — an account that was
            // half created. Signing out again avoids a session that can
            // reach nothing.
            await _client.auth.signOut();
            return const Err<AppUser>(
              AuthFailure(
                'This account is not set up yet. Ask your Area President to '
                'finish creating it.',
              ),
            );
          }
          await _claimCacheFor(value);
          return Ok<AppUser>(value);
      }
    } catch (error, stackTrace) {
      return Err<AppUser>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<AppUser?>> currentUser() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      return const Ok<AppUser?>(null);
    }
    return _loadProfileWithOfflineFallback(session.user.id);
  }

  @override
  Stream<AppUser?> authChanges() =>
      _client.auth.onAuthStateChange.asyncMap((AuthState state) async {
        final session = state.session;
        if (session == null) return null;
        final result = await _loadProfileWithOfflineFallback(session.user.id);
        return switch (result) {
          Ok(:final value) => value,
          Err() => null,
        };
      });

  @override
  Future<Result<void>> signOut() async {
    try {
      // GEN-06: the cached roster, bills and alerts belong to the person who
      // signed in, so they go. The outbox deliberately does not: signing out
      // with unsynced field work must not throw a morning of readings away.
      // The screen warns about that before it gets here.
      await _db.clearCachedData();
      await _client.auth.signOut();
      return const Ok<void>(null);
    } catch (error, stackTrace) {
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<void>> changePassword({required String newPassword}) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));

      final userId = _client.auth.currentUser?.id;
      if (userId != null) {
        // GEN-04: the temporary password has been replaced, so the flag that
        // locks the user to the change-password screen comes down.
        await _client
            .from('profiles')
            .update(<String, dynamic>{'must_change_password': false})
            .eq('id', userId);
      }
      return const Ok<void>(null);
    } catch (error, stackTrace) {
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<CreatedStaffAccount>> createStaffAccount({
    required String username,
    required String firstName,
    required String lastName,
    required String? contactNumber,
    required StaffRole role,
    required String temporaryPassword,
  }) async {
    try {
      // The signed-in Admin's JWT accompanies this request. The server checks
      // that it belongs to an Area President and derives the area from that
      // session. No privileged key or area id is sent by the app.
      final response = await _client.functions.invoke(
        'create-staff-account',
        body: <String, dynamic>{
          'username': username,
          'first_name': firstName,
          'last_name': lastName,
          'role': role.code,
          'temporary_password': temporaryPassword,
          'contact_number': contactNumber,
        },
      );

      final value = response.data;
      if (value is! Map) {
        return const Err<CreatedStaffAccount>(
          ServerFailure(
            'The server did not confirm that the staff account was created. '
            'Please check the account list before trying again.',
          ),
        );
      }

      if (value['ok'] != true) {
        final message = value['message'] is String
            ? value['message'] as String
            : 'The staff account could not be created. Please try again.';
        return Err<CreatedStaffAccount>(switch (value['kind']) {
          'validation' => ValidationFailure(message),
          'permission' => PermissionFailure(message),
          'conflict' => ConflictFailure(message),
          _ => ServerFailure(message),
        });
      }

      final id = value['id'];
      if (id is! String || id.isEmpty) {
        return const Err<CreatedStaffAccount>(
          ServerFailure(
            'The server did not confirm that the staff account was created. '
            'Please check the account list before trying again.',
          ),
        );
      }

      return Ok<CreatedStaffAccount>(
        CreatedStaffAccount(
          id: ProfileId(id),
          username: username,
          firstName: firstName,
          lastName: lastName,
          role: role,
          contactNumber: contactNumber,
          temporaryPassword: temporaryPassword,
        ),
      );
    } catch (error, stackTrace) {
      return Err<CreatedStaffAccount>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<List<ManagedAccount>>> managedAccounts(AreaId areaId) async {
    try {
      // Two reads, both under the Admin's own row-level security. A staff
      // profile carries its area. A consumer's login profile does not, so
      // households with a login are found through consumers.profile_id,
      // whose row is area-scoped.
      final staffRows = await _client
          .from('profiles')
          .select('id, first_name, last_name, username, role')
          .eq('area_id', areaId.value)
          .inFilter('role', <String>['meter_reader', 'cashier'])
          .eq('account_status', 'active')
          .order('last_name');

      final householdRows = await _client
          .from('consumers')
          .select('profile_id, first_name, last_name, consumer_no')
          .eq('area_id', areaId.value)
          .not('profile_id', 'is', null)
          .order('last_name');

      return Ok<List<ManagedAccount>>(<ManagedAccount>[
        for (final Map<String, dynamic> row in staffRows)
          ManagedAccount(
            id: ProfileId(row['id'] as String),
            firstName: row['first_name'] as String,
            lastName: row['last_name'] as String,
            kind: row['role'] == 'cashier'
                ? ManagedAccountKind.cashier
                : ManagedAccountKind.meterReader,
            reference: row['username'] as String,
          ),
        for (final Map<String, dynamic> row in householdRows)
          ManagedAccount(
            id: ProfileId(row['profile_id'] as String),
            firstName: row['first_name'] as String,
            lastName: row['last_name'] as String,
            kind: ManagedAccountKind.consumer,
            reference: row['consumer_no'] as String,
          ),
      ]);
    } catch (error, stackTrace) {
      return Err<List<ManagedAccount>>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<void>> resetAccountPassword({
    required ManagedAccount account,
    required String temporaryPassword,
  }) async {
    try {
      // As with createStaffAccount: the Admin's JWT goes with the request, and
      // the server decides whether this Area President may reset this
      // account. The client sends no area and holds no privileged key.
      final response = await _client.functions.invoke(
        'reset-account-password',
        body: <String, dynamic>{
          'profile_id': account.id.value,
          'temporary_password': temporaryPassword,
        },
      );

      final value = response.data;
      if (value is! Map) {
        return const Err<void>(
          ServerFailure(
            'The server did not confirm the password reset. Please try again.',
          ),
        );
      }

      if (value['ok'] != true) {
        final message = value['message'] is String
            ? value['message'] as String
            : 'The password could not be reset. Please try again.';
        return Err<void>(switch (value['kind']) {
          'validation' => ValidationFailure(message),
          'permission' => PermissionFailure(message),
          'conflict' => ConflictFailure(message),
          _ => ServerFailure(message),
        });
      }

      return const Ok<void>(null);
    } catch (error, stackTrace) {
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<List<HouseholdWithoutLogin>>> householdsWithoutLogin(
    AreaId areaId,
  ) async {
    try {
      // Under the Admin's own row-level security, which already confines
      // households to their area. Inactive households are left out: the
      // server would refuse them a sign-in anyway.
      final rows = await _client
          .from('consumers')
          .select('id, consumer_no, first_name, last_name, purok')
          .eq('area_id', areaId.value)
          .eq('account_status', 'active')
          .isFilter('profile_id', null)
          .order('last_name');

      return Ok<List<HouseholdWithoutLogin>>(<HouseholdWithoutLogin>[
        for (final Map<String, dynamic> row in rows)
          HouseholdWithoutLogin(
            id: ConsumerId(row['id'] as String),
            consumerNo: ConsumerNumber(row['consumer_no'] as String),
            firstName: row['first_name'] as String,
            lastName: row['last_name'] as String,
            purok: row['purok'] as String?,
          ),
      ]);
    } catch (error, stackTrace) {
      return Err<List<HouseholdWithoutLogin>>(
        FailureMapper.from(error, stackTrace),
      );
    }
  }

  @override
  Future<Result<CreatedHouseholdLogin>> createHouseholdLogin({
    required HouseholdWithoutLogin household,
    required String username,
    required String temporaryPassword,
  }) async {
    try {
      // As with createStaffAccount: the Admin's JWT goes with the request, and
      // the server checks that the household is in their area and has no
      // sign-in. The household's name is read from its record there, not
      // sent from here.
      final response = await _client.functions.invoke(
        'create-household-login',
        body: <String, dynamic>{
          'consumer_id': household.id.value,
          'username': username,
          'temporary_password': temporaryPassword,
        },
      );

      final value = response.data;
      if (value is! Map) {
        return const Err<CreatedHouseholdLogin>(
          ServerFailure(
            'The server did not confirm the household sign-in. Please check '
            'the household list before trying again.',
          ),
        );
      }

      if (value['ok'] != true) {
        final message = value['message'] is String
            ? value['message'] as String
            : 'The household sign-in could not be created. Please try again.';
        return Err<CreatedHouseholdLogin>(switch (value['kind']) {
          'validation' => ValidationFailure(message),
          'permission' => PermissionFailure(message),
          'conflict' => ConflictFailure(message),
          _ => ServerFailure(message),
        });
      }

      final id = value['id'];
      if (id is! String || id.isEmpty) {
        return const Err<CreatedHouseholdLogin>(
          ServerFailure(
            'The server did not confirm the household sign-in. Please check '
            'the household list before trying again.',
          ),
        );
      }

      return Ok<CreatedHouseholdLogin>(
        CreatedHouseholdLogin(
          id: ProfileId(id),
          username: value['username'] is String
              ? value['username'] as String
              : username,
          household: household,
          temporaryPassword: temporaryPassword,
        ),
      );
    } catch (error, stackTrace) {
      return Err<CreatedHouseholdLogin>(FailureMapper.from(error, stackTrace));
    }
  }

  Future<Result<AppUser?>> _loadProfile(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select(ProfileDto.columns)
          .eq('id', userId)
          .maybeSingle();

      if (row == null) {
        return const Ok<AppUser?>(null);
      }
      if (row['account_status'] != 'active') {
        return const Err<AppUser?>(
          AuthFailure(
            'This account is not active. Ask your Area President to activate '
            'it.',
          ),
        );
      }
      return Ok<AppUser?>(ProfileDto.fromJson(row));
    } catch (error, stackTrace) {
      return Err<AppUser?>(FailureMapper.from(error, stackTrace));
    }
  }

  /// Loads the authoritative profile when possible, but keeps an existing
  /// authenticated session usable offline. The fallback is accepted only
  /// for a network failure and only when the encrypted cache belongs to the
  /// exact profile id in Supabase's persisted session.
  Future<Result<AppUser?>> _loadProfileWithOfflineFallback(
    String userId,
  ) async {
    final remote = await _loadProfile(userId);
    if (remote case Ok(:final value)) {
      if (value != null) await _claimCacheFor(value);
      return remote;
    }
    if (remote case Err(failure: NetworkFailure())) {
      final cached = await _cachedProfileFor(userId);
      if (cached != null) return Ok<AppUser?>(cached);
    }
    return remote;
  }

  Future<AppUser?> _cachedProfileFor(String userId) async {
    final row = await _db.select(_db.cacheOwner).getSingleOrNull();
    if (row == null || row.profileId != userId) return null;
    if (row.username == null ||
        row.firstName == null ||
        row.lastName == null ||
        row.mustChangePassword == null) {
      return null;
    }

    return ProfileDto.fromJson(<String, dynamic>{
      'id': row.profileId,
      'username': row.username,
      'first_name': row.firstName,
      'last_name': row.lastName,
      'role': row.role,
      'area_id': row.areaId,
      'must_change_password': row.mustChangePassword,
      'account_status': 'active',
    });
  }

  /// SYS-05: records who this cache belongs to, and empties it first if the
  /// previous owner was somebody else. Two staff sharing one phone must not
  /// be able to see each other's area.
  Future<void> _claimCacheFor(AppUser user) async {
    final existing = await _db.select(_db.cacheOwner).getSingleOrNull();
    if (existing != null && existing.profileId != user.id.value) {
      await _db.clearCachedData();
    }
    await _db
        .into(_db.cacheOwner)
        .insertOnConflictUpdate(
          CacheOwnerCompanion.insert(
            id: const Value<int>(1),
            profileId: user.id.value,
            username: Value<String?>(user.username),
            firstName: Value<String?>(user.firstName),
            lastName: Value<String?>(user.lastName),
            mustChangePassword: Value<bool?>(user.mustChangePassword),
            role: user.roleCode,
            areaId: Value<String?>(user.areaId?.value),
            cachedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
  }
}
