import 'dart:convert';


import '../../core/errors/app_failure.dart';
import '../supabase/failure_mapper.dart';
import 'app_database.dart';

/// The last answer the server gave to a read, kept so the same screen still
/// opens with no signal.
///
/// For the staff screens that have no dedicated cache table: the Admin's
/// queue and notices, the Cashier's consumer list, bills and receipts. The
/// rows are stored exactly as the server returned them, so each repository
/// keeps parsing them the way it already does and nothing about what a
/// screen shows changes between online and offline, except its age.
///
/// Scoped like every other cache: it holds only the signed-in person's own
/// data, and [AppDatabase.clearCachedData] empties it on sign-out or when a
/// different account signs in on this phone.
class QueryCache {
  final AppDatabase _db;

  const QueryCache(this._db);

  /// Runs [fetch]. On success the rows are saved under [key] and returned.
  /// When the server cannot be reached, the rows last saved under [key] are
  /// returned instead; with nothing saved, the original error is rethrown so
  /// the caller reports "no connection" as before. Any other error, such as
  /// a refusal from the server, is rethrown untouched: a saved copy must
  /// never paper over a real problem.
  Future<List<Map<String, dynamic>>> rows(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    try {
      final List<Map<String, dynamic>> fresh = await fetch();
      await _save(key, fresh);
      return fresh;
    } catch (error, stackTrace) {
      if (FailureMapper.from(error, stackTrace) is! NetworkFailure) rethrow;
      final List<Map<String, dynamic>>? saved = await _load(key);
      if (saved == null) rethrow;
      return saved;
    }
  }

  Future<void> _save(String key, List<Map<String, dynamic>> rows) async {
    try {
      await _db
          .into(_db.cachedQueries)
          .insertOnConflictUpdate(
            CachedQueriesCompanion.insert(
              queryKey: key,
              rowsJson: jsonEncode(rows),
              savedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          );
    } catch (_) {
      // Failing to save must not fail a read that succeeded online.
    }
  }

  Future<List<Map<String, dynamic>>?> _load(String key) async {
    try {
      final row = await (_db.select(
        _db.cachedQueries,
      )..where((table) => table.queryKey.equals(key))).getSingleOrNull();
      if (row == null) return null;
      return (jsonDecode(row.rowsJson) as List<dynamic>)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }
}
