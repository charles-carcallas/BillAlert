import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/value_objects/money.dart';
import '../local/app_database.dart';
import '../local/pending_fund_request.dart';
import '../local/query_cache.dart';

class SettlementSnapshot {
  SettlementSnapshot(this.data);
  final Map<String, dynamic> data;
  Money money(String key) => Money.tryParse('${data[key] ?? 0}') ?? Money.zero;
  List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
}

class SettlementRepository {
  const SettlementRepository(this.client, this.database);
  final SupabaseClient client;
  final AppDatabase database;

  Future<SettlementSnapshot> snapshot(String scope) async {
    final rows = await QueryCache(database).rows('settlement:$scope', () async {
      final data = await client.rpc('fn_settlement_snapshot');
      return [Map<String, dynamic>.from(data as Map)];
    });
    return SettlementSnapshot(rows.single);
  }

  Future<void> payCompensation(String month, String reader) async {
    await client.rpc(
      'fn_pay_reader_compensation',
      params: {'p_month': month, 'p_reader': reader},
    );
  }

  Future<void> reverseCompensation(String id, String reason) async {
    await client.rpc(
      'fn_reverse_reader_compensation',
      params: {'p_id': id, 'p_reason': reason},
    );
  }

  Future<void> completeTrip(String trip, List<String> billIds) async {
    await client.rpc(
      'fn_complete_boheco_trip',
      params: {'p_trip': trip, 'p_expected_bill_ids': billIds},
    );
  }

  Future<void> close(String month) async {
    await client.rpc('fn_close_boheco_trip', params: {'p_month': month});
  }

  Future<void> entry(
    Money amount,
    String kind,
    String reason,
    String uuid, {
    required String owner,
  }) async {
    if (client.auth.currentUser?.id != owner.split(':').first) {
      throw StateError('Sign in as the owner of this reserve fund entry.');
    }
    final store = FundRequestStore(database);
    final wasPending = await store.read(owner) != null;
    final request = PendingFundRequest(
      amount.toDatabaseString(),
      kind,
      reason,
      uuid,
    );
    await store.save(owner, request);
    if (client.auth.currentUser?.id != owner.split(':').first) {
      throw StateError('Sign in as the owner to check this pending entry.');
    }
    try {
      await client.rpc('fn_pondo_entry', params: request.params);
    } on PostgrestException catch (e) {
      // These are explicit transactional refusals, not an uncertain transport
      // failure. An interrupted/unknown result must keep its original UUID.
      if (!wasPending &&
          (e.code == 'P0001' ||
              (e.code?.startsWith('22') ?? false) ||
              (e.code?.startsWith('23') ?? false))) {
        await store.clear(owner, request);
      }
      rethrow;
    }
    await store.clear(owner, request);
  }

  Future<PendingFundRequest?> pendingEntry(String owner) =>
      FundRequestStore(database).read(owner);

  Future<void> allocate(
    String trip,
    List<Map<String, dynamic>> bills,
    String reader,
  ) async {
    await client.rpc(
      'fn_allocate_boheco_trip',
      params: {
        'p_trip': trip,
        'p_bill_ids': bills.map((b) => b['bill_id']).toList(),
        'p_expected_amounts': bills
            .map((b) => '${b['consumer_amount']}')
            .toList(),
        'p_reader': reader,
      },
    );
  }

  Future<void> refer(String bill) async {
    await client.rpc('fn_confirm_boheco_referral', params: {'p_bill': bill});
  }

  Future<void> verify(
    String bill,
    Money amount,
    String reference,
    DateTime paidAt,
    String evidence,
    String uuid,
  ) async {
    await client.rpc(
      'fn_confirm_boheco_payment',
      params: {
        'p_bill': bill,
        'p_amount': amount.toDatabaseString(),
        'p_reference': reference,
        'p_paid_at': paidAt.toUtc().toIso8601String(),
        'p_evidence': evidence,
        'p_client_uuid': uuid,
      },
    );
  }

  Future<void> correct(
    String bill,
    String reason, {
    required String action,
    required String updatedAt,
    required String uuid,
  }) async {
    await client.rpc(
      'fn_correct_settlement_checked',
      params: {
        'p_bill': bill,
        'p_reason': reason,
        'p_action': action,
        'p_expected_updated_at': updatedAt,
        'p_client_uuid': uuid,
      },
    );
  }

  Future<void> supply(String bill, String status, String evidence) async {
    await client.rpc(
      'fn_record_supply_status',
      params: {'p_bill': bill, 'p_status': status, 'p_evidence': evidence},
    );
  }

  Future<List<Map<String, dynamic>>> forHousehold(String id) =>
      QueryCache(database).rows(
        'household_settlements:$id',
        () => client.from('v_bill_settlement').select().eq('consumer_id', id),
      );
}
