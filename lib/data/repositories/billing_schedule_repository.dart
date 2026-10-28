import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/billing_schedule.dart';
import '../local/app_database.dart';
import '../local/query_cache.dart';

class BillingScheduleRepository {
  const BillingScheduleRepository(this.client, this.database);
  final SupabaseClient client;
  final AppDatabase database;
  Future<BillingSchedule> load(String scope) async {
    final rows = await QueryCache(database).rows(
      'billing_schedule:$scope',
      () async => [
        Map<String, dynamic>.from(
          await client.rpc('fn_get_billing_schedule') as Map,
        ),
      ],
    );
    return BillingSchedule.fromJson(rows.single);
  }

  Future<BillingSchedule> save(
    BillingSchedule value,
    String clientUuid, {
    required String scope,
  }) async {
    final epoch = database.cacheEpoch;
    final data = await client.rpc(
      'fn_save_billing_schedule',
      params: {
        'p_due_day': value.dueDay,
        'p_cutoff_day': value.cutoffDay,
        'p_cutoff_minutes': value.cutoffMinutes,
        'p_expected_version': value.version,
        'p_client_uuid': clientUuid,
      },
    );
    final row = Map<String, dynamic>.from(data as Map);
    // Cache only for the same signed-in session that started this save.
    if (epoch == database.cacheEpoch) {
      await QueryCache(
        database,
      ).rows('billing_schedule:$scope', () async => [row]);
    }
    return BillingSchedule.fromJson(row);
  }
}
