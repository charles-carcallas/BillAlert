import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/notifications/phone_alerts.dart';

/// Urgent due-date alerts, on or off, kept on this phone only.
///
/// Stored as "off", so on is the default without anything being written, and
/// every read that fails comes back on. A setting nobody can read should not
/// quietly soften a reminder the household never asked to soften.
///
/// Read from the background check's isolate as well as the app's, which is
/// why this is secure storage rather than something held in memory.
class SecureUrgentAlertsSetting implements UrgentAlertsSetting {
  static const String _offKey = 'billalert_urgent_alerts_off';

  final FlutterSecureStorage _storage;

  const SecureUrgentAlertsSetting([
    this._storage = const FlutterSecureStorage(),
  ]);

  @override
  Future<bool> isOn() async {
    try {
      return await _storage.read(key: _offKey) != 'true';
    } catch (_) {
      return true;
    }
  }

  @override
  Future<void> turnOn() => _storage.delete(key: _offKey);

  @override
  Future<void> turnOff() => _storage.write(key: _offKey, value: 'true');
}
