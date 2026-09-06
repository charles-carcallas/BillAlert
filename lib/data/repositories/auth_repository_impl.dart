import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
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

  @override
  Future<Result<AppUser>> signIn({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _client.auth.signInWithPassword(
        email: AppConfig.emailForUsername(username),
        password: password,
      );

      final user = response.user;
      if (user == null) {
        return const Err<AppUser>(AuthFailure());
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
            return const Err<AppUser>(AuthFailure(
              'This account is not set up yet. Ask your Area President to '
              'finish creating it.',
            ));
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
    return _loadProfile(session.user.id);
  }

  @override
  Stream<AppUser?> authChanges() =>
      _client.auth.onAuthStateChange.asyncMap((AuthState state) async {
        final session = state.session;
        if (session == null) return null;
        final result = await _loadProfile(session.user.id);
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
        return const Err<AppUser?>(AuthFailure(
          'This account is not active. Ask your Area President to activate '
          'it.',
        ));
      }
      return Ok<AppUser?>(ProfileDto.fromJson(row));
    } catch (error, stackTrace) {
      return Err<AppUser?>(FailureMapper.from(error, stackTrace));
    }
  }

  /// SYS-05: records who this cache belongs to, and empties it first if the
  /// previous owner was somebody else. Two staff sharing one phone must not
  /// be able to see each other's area.
  Future<void> _claimCacheFor(AppUser user) async {
    final existing = await _db.select(_db.cacheOwner).getSingleOrNull();
    if (existing != null && existing.profileId != user.id.value) {
      await _db.clearCachedData();
    }
    await _db.into(_db.cacheOwner).insertOnConflictUpdate(
          CacheOwnerCompanion.insert(
            id: const Value<int>(1),
            profileId: user.id.value,
            role: user.roleCode,
            areaId: Value<String?>(user.areaId?.value),
            cachedAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
  }
}
