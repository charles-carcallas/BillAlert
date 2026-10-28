import 'dart:convert';
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
    'lookup filters by transaction and never substitutes cached history when offline',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      var offline = false;
      final queries = <Uri>[];
      final client = SupabaseClient(
        'https://billalert.test',
        'test-key',
        httpClient: MockClient((request) async {
          queries.add(request.url);
          if (offline) throw http.ClientException('No connection');
          final Object body;
          if (request.url.path.endsWith('payment_transactions')) {
            expect(request.url.queryParameters['id'], 'eq.exact-transaction');
            body = {'receipt_no': 'EXACT'};
          } else {
            final receipt =
                request.url.queryParameters['receipt_no'] == 'eq.EXACT'
                ? 'EXACT'
                : 'OLDER';
            body = [
              {
                'payment_id': 'payment',
                'receipt_no': receipt,
                'consumer_id': 'house',
                'bill_id': 'bill',
                'bill_no': 'BILL',
                'cycle_label': '2026-10',
                'paid_at': '2026-10-02T01:00:00Z',
                'transaction_total': '100.00',
                'amount_paid': '100.00',
              },
            ];
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final repo = PaymentRepositoryImpl(db, client);
      expect(
        await repo.historyFor(const ConsumerId('house')),
        isA<Ok<List<PaymentSummary>>>(),
      );
      expect(
        (await repo.byTransaction('exact-transaction') as Ok<PaymentSummary?>)
            .value
            ?.receiptNo,
        'EXACT',
      );
      offline = true;
      expect(
        await repo.byTransaction('exact-transaction'),
        isA<Err<PaymentSummary?>>(),
      );
      expect(
        queries.any((q) => q.queryParameters['receipt_no'] == 'eq.EXACT'),
        isTrue,
      );
      await db.close();
      await client.dispose();
    },
  );
}
