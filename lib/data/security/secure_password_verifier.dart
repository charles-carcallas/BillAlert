import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/security/password_verifier.dart';
import '../../domain/value_objects/ids.dart';

/// [PasswordVerifier] as PBKDF2-HMAC-SHA256 with a random salt, stored in the
/// same Keystore-backed storage as the database key.
///
/// Stored as `iterations:salt:hash`, base64, one entry per profile. A read or
/// write that fails is treated as "nothing kept": the worst outcome is that
/// the offline password route is unavailable, never that a wrong password
/// gets through.
class SecurePasswordVerifier implements PasswordVerifier {
  static const String _keyPrefix = 'billalert_password_check_';

  /// Slow enough that a copied hash is expensive to guess against, quick
  /// enough on a budget Android phone that unlocking does not feel stuck.
  static const int iterations = 60000;

  final FlutterSecureStorage _storage;

  const SecurePasswordVerifier([this._storage = const FlutterSecureStorage()]);

  @override
  Future<void> remember(ProfileId profile, String password) async {
    try {
      final Random random = Random.secure();
      final List<int> salt = List<int>.generate(16, (_) => random.nextInt(256));
      final List<int> hash = await _derive(password, salt, iterations);
      await _storage.write(
        key: '$_keyPrefix${profile.value}',
        value: '$iterations:${base64Encode(salt)}:${base64Encode(hash)}',
      );
    } catch (_) {
      // Not saving only means the offline password route stays unavailable.
    }
  }

  @override
  Future<bool?> matches(ProfileId profile, String password) async {
    final String? stored;
    try {
      stored = await _storage.read(key: '$_keyPrefix${profile.value}');
    } catch (_) {
      return null;
    }
    if (stored == null) return null;

    final List<String> parts = stored.split(':');
    if (parts.length != 3) return null;
    final int? rounds = int.tryParse(parts[0]);
    if (rounds == null) return null;

    try {
      final List<int> salt = base64Decode(parts[1]);
      final List<int> expected = base64Decode(parts[2]);
      final List<int> actual = await _derive(password, salt, rounds);
      return _constantTimeEquals(actual, expected);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> forget(ProfileId profile) async {
    try {
      await _storage.delete(key: '$_keyPrefix${profile.value}');
    } catch (_) {}
  }

  /// Off the UI thread: sixty thousand HMAC rounds would drop frames.
  static Future<List<int>> _derive(
    String password,
    List<int> salt,
    int rounds,
  ) => Isolate.run(() => pbkdf2Sha256(utf8.encode(password), salt, rounds));

  /// PBKDF2 (RFC 8018) with HMAC-SHA256, one 32-byte block.
  static List<int> pbkdf2Sha256(
    List<int> password,
    List<int> salt,
    int rounds,
  ) {
    final Hmac hmac = Hmac(sha256, password);
    List<int> u = hmac.convert(<int>[...salt, 0, 0, 0, 1]).bytes;
    final List<int> result = List<int>.of(u);
    for (int i = 1; i < rounds; i++) {
      u = hmac.convert(u).bytes;
      for (int j = 0; j < result.length; j++) {
        result[j] ^= u[j];
      }
    }
    return result;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int difference = 0;
    for (int i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
