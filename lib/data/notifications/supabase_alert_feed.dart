import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/notifications/phone_alerts.dart';
import '../../domain/value_objects/ids.dart';
import '../repositories/bill_repository_impl.dart';
import '../supabase/failure_mapper.dart';

/// The household's notifications and unpaid bills, straight from Supabase,
/// under the household's own row-level security.
///
/// No cache and no repository that holds one: this runs in the background
/// isolate as well as the app's, and must not open the encrypted database.
class SupabaseAlertFeed implements AlertFeed {
  final SupabaseClient _client;

  const SupabaseAlertFeed(this._client);

  @override
  Future<Result<ConsumerId?>> signedInHousehold() async {
    try {
      final String? profileId = _client.auth.currentUser?.id;
      if (profileId == null) return const Ok<ConsumerId?>(null);

      // Filtered by profile, not left to row-level security alone. Staff can
      // see every household in their area, and an area with a single
      // household would otherwise make a meter reader look like that
      // household — and receive its notifications.
      final row = await _client
          .from('consumers')
          .select('id')
          .eq('profile_id', profileId)
          .maybeSingle();

      return Ok<ConsumerId?>(
        row == null ? null : ConsumerId(row['id'] as String),
      );
    } catch (error, stackTrace) {
      return Err<ConsumerId?>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<List<PendingPhoneAlert>>> pendingAlerts(
    ConsumerId household,
  ) async {
    try {
      final rows = await _client
          .from('notifications')
          .select('id, notif_type')
          .eq('consumer_id', household.value)
          .eq('channel', 'push')
          .eq('status', 'pending')
          .order('created_at')
          // A phone that was off for a month should not bury its household
          // under every notice at once.
          .limit(10);

      return Ok<List<PendingPhoneAlert>>(<PendingPhoneAlert>[
        for (final Map<String, dynamic> row in rows)
          PendingPhoneAlert(
            id: NotificationId(row['id'] as String),
            type: row['notif_type'] as String? ?? '',
          ),
      ]);
    } catch (error, stackTrace) {
      return Err<List<PendingPhoneAlert>>(
        FailureMapper.from(error, stackTrace),
      );
    }
  }

  @override
  Future<Result<void>> markShown(NotificationId id) async {
    try {
      // `notif_consumer_mark_read` lets a household update its own rows. The
      // extra filters keep this to what it claims: a push notice, moving from
      // pending to sent, once.
      await _client
          .from('notifications')
          .update(<String, dynamic>{
            'status': 'sent',
            'sent_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', id.value)
          .eq('channel', 'push')
          .eq('status', 'pending');

      return const Ok<void>(null);
    } catch (error, stackTrace) {
      return Err<void>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<List<Bill>>> unpaidBills(ConsumerId household) async {
    try {
      final rows = await _client
          .from('v_bill_status')
          .select(BillRepositoryImpl.billColumns)
          .eq('consumer_id', household.value)
          .not('total_amount', 'is', null)
          .neq('status', 'paid');

      return Ok<List<Bill>>(rows.map(Bill.fromJson).toList());
    } catch (error, stackTrace) {
      return Err<List<Bill>>(FailureMapper.from(error, stackTrace));
    }
  }

  @override
  Future<Result<int?>> reminderDaysBeforeDue() async {
    try {
      // `settings_read` lets any signed-in user read the settings row.
      final row = await _client
          .from('settings')
          .select('predue_reminder_days')
          .eq('id', 1)
          .maybeSingle();

      final Object? days = row?['predue_reminder_days'];
      return Ok<int?>(days is int ? days : null);
    } catch (error, stackTrace) {
      return Err<int?>(FailureMapper.from(error, stackTrace));
    }
  }
}
