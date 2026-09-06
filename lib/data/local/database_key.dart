import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The SQLCipher key for the local cache.
///
/// SYS-05 requires the on-device cache to be encrypted. The key is generated
/// once on this phone, kept in the platform credential store (Android
/// Keystore), and never appears in source, in SharedPreferences, in a .env
/// file, or in a log line. Losing it means the cache cannot be opened, which
/// is the correct outcome: it is a cache, and it can be refilled from the
/// server.
class DatabaseKey {
  static const String _storageKey = 'billalert_db_key';

  /// Default options. On Android that means AES-GCM with the key held in the
  /// Android Keystore, which is what flutter_secure_storage 11 uses for
  /// everything — the older EncryptedSharedPreferences backend was removed.
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  const DatabaseKey._();

  /// Reads the key, generating and storing one the first time the app runs.
  static Future<String> readOrCreate() async {
    final existing = await _storage.read(key: _storageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final created = _generate();
    await _storage.write(key: _storageKey, value: created);
    return created;
  }

  /// 32 random bytes, base64 encoded. `Random.secure()` is the
  /// cryptographically secure generator; the default `Random()` is not, and
  /// using it here would make the key guessable.
  static String _generate() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (int _) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  /// Only for signing out on a shared phone, if the team ever decides the
  /// cache should be destroyed rather than emptied.
  static Future<void> delete() => _storage.delete(key: _storageKey);
}
