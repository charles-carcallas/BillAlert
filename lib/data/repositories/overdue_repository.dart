import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/bill.dart';
import '../../domain/value_objects/money.dart';
import '../local/app_database.dart';
import '../local/query_cache.dart';

final class OverdueBill {
  final Bill bill;
  final String household;
  final String? approval;
  final String? approvedAmount;
  final String? consumerNo, consumerName, purok;
  const OverdueBill(
    this.bill,
    this.household,
    this.approval,
    this.approvedAmount, {
    this.consumerNo,
    this.consumerName,
    this.purok,
  });
  bool get isApproved => approval == 'approved' && _matchesBalance;
  bool get isRequested => approval == 'requested' && _matchesBalance;
  bool get _matchesBalance =>
      Money.tryParse(approvedAmount ?? '') == bill.balance;
}

final class OverdueRepository {
  final SupabaseClient client;
  final AppDatabase database;
  const OverdueRepository(this.client, this.database);

  Future<List<OverdueBill>> list(String area, String owner) async {
    final rows = await QueryCache(database).rows(
      'overdue:$owner:$area',
      () => client
          .from('v_overdue_collection')
          .select()
          .eq('area_id', area)
          .order('due_date'),
    );
    return rows
        .map(
          (r) => OverdueBill(
            Bill.fromJson({...r, 'bill_id': r['id']}),
            '${r['first_name']} ${r['last_name']} · ${r['consumer_no']}',
            r['approval_state'] as String?,
            r['approved_amount']?.toString(),
            consumerNo: r['consumer_no'] as String?,
            consumerName: '${r['first_name']} ${r['last_name']}',
            purok: r['purok'] as String?,
          ),
        )
        .toList();
  }

  Future<void> decide(String bill, String action) => client.rpc(
    'fn_overdue_decision',
    params: {'p_bill_id': bill, 'p_action': action},
  );

  Future<void> authorizeBatch(List<OverdueBill> rows) {
    if (rows.isEmpty ||
        rows.any((row) => row.bill.consumerId != rows.first.bill.consumerId)) {
      throw ArgumentError('Select overdue bills for one household.');
    }
    return client.rpc(
      'fn_authorize_overdue_batch',
      params: {
        'p_consumer_id': rows.first.bill.consumerId.value,
        'p_bill_ids': rows.map((row) => row.bill.id.value).toList(),
        'p_expected_amounts': rows
            .map((row) => row.bill.balance.toDatabaseString())
            .toList(),
      },
    );
  }

  Future<void> requestHousehold(List<OverdueBill> rows) {
    if (rows.isEmpty ||
        rows.any((r) => r.bill.consumerId != rows.first.bill.consumerId)) {
      throw ArgumentError('Select overdue bills for one household.');
    }
    return client.rpc(
      'fn_request_overdue_household',
      params: {
        'p_consumer_id': rows.first.bill.consumerId.value,
        'p_bill_ids': rows.map((r) => r.bill.id.value).toList(),
        'p_expected_amounts': rows
            .map((r) => r.bill.balance.toDatabaseString())
            .toList(),
      },
    );
  }

  /// Completed collections and revoked decisions, including earlier events.
  Future<List<Map<String, dynamic>>> history(
    String area,
    String owner,
  ) => QueryCache(database).rows(
    'overdue-history:$owner:$area',
    () => client
        .from('overdue_collection_audit')
        .select(
          'id,action,amount,occurred_at,bills!inner(bill_no,consumers!inner(first_name,last_name,consumer_no,area_id))',
        )
        .eq('bills.consumers.area_id', area)
        .inFilter('action', ['consumed', 'revoked'])
        .order('occurred_at', ascending: false),
  );
}
