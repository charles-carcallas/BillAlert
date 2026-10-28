import 'dart:convert';
import 'package:drift/drift.dart';
import 'app_database.dart';

class PendingFundRequest {
  const PendingFundRequest(this.amount, this.kind, this.reason, this.uuid);
  final String amount, kind, reason, uuid;
  Map<String, dynamic> get params => {
    'p_amount': amount,
    'p_kind': kind,
    'p_reason': reason,
    'p_client_uuid': uuid,
  };
  String get encoded => jsonEncode(params);
  factory PendingFundRequest.decode(String value) {
    final p = jsonDecode(value) as Map<String, dynamic>;
    return PendingFundRequest(
      p['p_amount'] as String,
      p['p_kind'] as String,
      p['p_reason'] as String,
      p['p_client_uuid'] as String,
    );
  }
}

class FundRequestStore {
  const FundRequestStore(this.db);
  final AppDatabase db;
  Future<PendingFundRequest?> read(String owner) async {
    final row = await db
        .customSelect(
          'SELECT payload FROM pending_fund_requests WHERE owner = ?',
          variables: [Variable.withString(owner)],
        )
        .getSingleOrNull();
    return row == null
        ? null
        : PendingFundRequest.decode(row.read<String>('payload'));
  }

  Future<void> save(String owner, PendingFundRequest request) =>
      db.transaction(() async {
        final old = await read(owner);
        if (old != null && old.encoded != request.encoded) {
          throw StateError(
            'Resolve the previous reserve fund entry before recording another.',
          );
        }
        if (old == null) {
          await db.customStatement(
            'INSERT INTO pending_fund_requests(owner,payload) VALUES (?,?)',
            [owner, request.encoded],
          );
        }
      });
  Future<void> clear(String owner, PendingFundRequest request) =>
      db.customStatement(
        'DELETE FROM pending_fund_requests WHERE owner = ? AND payload = ?',
        [owner, request.encoded],
      );
}
