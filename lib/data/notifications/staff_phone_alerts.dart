import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../domain/notifications/phone_alerts.dart';

/// A stable installation id; server leases prevent foreground/background races.
Future<String> staffAlertDeviceId() async {
  const storage = FlutterSecureStorage();
  const key = 'billalert_staff_alert_device';
  final saved = await storage.read(key: key);
  if (saved != null) return saved;
  final id = const Uuid().v4();
  await storage.write(key: key, value: id);
  return id;
}

Future<void> refreshStaffPhoneAlerts(
  SupabaseClient client,
  PhoneNotifier phone,
  String device,
) async {
  final owner = client.auth.currentUser?.id;
  if (owner == null || !await phone.canNotify()) return;
  final rows = await client.rpc<List<dynamic>>(
    'fn_claim_staff_alerts',
    params: {'p_device': device},
  );
  for (final raw in rows) {
    final row = raw as Map<String, dynamic>;
    if (client.auth.currentUser?.id != owner || row['recipient_id'] != owner) {
      return;
    }
    final id = row['id'] as String;
    await phone.show(
      PhoneNotice(
        id: stableNoticeId('staff:$owner:$id'),
        title: row['title'] as String,
        body: row['body'] as String,
        payload: 'staff:$owner:${row['destination']}',
      ),
    );
    if (client.auth.currentUser?.id != owner) {
      await phone.cancel(stableNoticeId('staff:$owner:$id'));
      return;
    }
    await client.rpc(
      'fn_staff_alert_shown',
      params: {'p_alert': id, 'p_device': device},
    );
  }
}
