import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/security/fingerprint_setting.dart';
import '../../domain/value_objects/ids.dart';

/// Fingerprint sign-in's on/off state, kept on this phone only.
///
/// It holds a profile id, not a credential, so it is not a secret. It lives
/// in the same Keystore-backed store as the database key anyway, rather than
/// in the app's plain preferences file, so switching the lock off takes more
/// than editing that file.
///
/// Every read fails OFF. A setting that cannot be read leaves the app doing
/// exactly what it did before this feature existed: the restored session
/// opens. Failing the other way would lock somebody behind a prompt for a
/// setting nobody can see or change.
class SecureFingerprintSetting implements FingerprintSetting {
  static const String _onForKey = 'billalert_fingerprint_on_for';
  static const String _offeredToKey = 'billalert_fingerprint_offered_to';

  final FlutterSecureStorage _storage;

  const SecureFingerprintSetting([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<bool> isOnFor(ProfileId profile) async =>
      await _read(_onForKey) == profile.value;

  @override
  Future<void> turnOnFor(ProfileId profile) =>
      _storage.write(key: _onForKey, value: profile.value);

  @override
  Future<void> turnOff() => _storage.delete(key: _onForKey);

  @override
  Future<bool> wasOfferedTo(ProfileId profile) async =>
      (await _offeredTo()).contains(profile.value);

  @override
  Future<void> markOfferedTo(ProfileId profile) async {
    final Set<String> offered = await _offeredTo();
    offered.add(profile.value);
    await _storage.write(key: _offeredToKey, value: offered.join(','));
  }

  Future<Set<String>> _offeredTo() async {
    final String? raw = await _read(_offeredToKey);
    if (raw == null || raw.isEmpty) return <String>{};
    return raw.split(',').toSet();
  }

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }
}
