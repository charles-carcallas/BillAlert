import 'dart:convert';
import 'dart:io';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/payment_repository_impl.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'reserve fund repayment remains a receipt offline and never enters BOHECO remittance',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      var offline = false;
      final client = SupabaseClient(
        'https://billalert.test',
        'test',
        httpClient: MockClient((request) async {
          if (offline) throw const SocketException('offline');
          return http.Response(
            jsonEncode([
              for (final kind in ['regular', 'pondo_repayment'])
                {
                  'payment_id': kind,
                  'receipt_no': kind,
                  'consumer_id': 'home',
                  'consumer_name': 'Test',
                  'bill_id': kind,
                  'bill_no': kind,
                  'cycle_label': 'October 2026',
                  'paid_at': '2026-10-02T01:00:00Z',
                  'transaction_total': 250,
                  'amount_paid': 250,
                  'boheco_share': 249.40,
                  'collection_kind': kind,
                },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(() async {
        await db.close();
        await client.dispose();
      });
      final repo = PaymentRepositoryImpl(db, client);
      final from = DateTime.utc(2026, 10, 1), until = DateTime.utc(2026, 11, 1);
      final live =
          await repo.collectedInArea(
                const AreaId('area'),
                from: from,
                until: until,
              )
              as Ok<List<PaymentSummary>>;
      expect(live.value.single.receiptNo, 'regular');
      final history =
          await repo.historyFor(const ConsumerId('home'))
              as Ok<List<PaymentSummary>>;
      expect(history.value.where((r) => r.isPondoRepayment).length, 1);
      offline = true;
      final cached =
          await repo.collectedInArea(
                const AreaId('area'),
                from: from,
                until: until,
              )
              as Ok<List<PaymentSummary>>;
      expect(cached.value.single.receiptNo, 'regular');
      final saved =
          await repo.historyFor(const ConsumerId('home'))
              as Ok<List<PaymentSummary>>;
      expect(saved.value.where((r) => r.isPondoRepayment).length, 1);
    },
  );
}
