import 'dart:convert';
import 'dart:io';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/bill_repository_impl.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('BOHECO coverage survives offline history and bill details', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var offline = false;
    final client = SupabaseClient(
      'https://waiver.test',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      httpClient: MockClient((request) async {
        if (offline) throw const SocketException('offline');
        expect(
          request.url.queryParameters['select'],
          contains('waiver_amount'),
        );
        return http.Response(
          jsonEncode([
            {
              'bill_id': 'bill',
              'bill_no': 'B-1',
              'consumer_id': 'household',
              'cycle_year': 2026,
              'cycle_month': 10,
              'consumption': 10,
              'total_amount': 530,
              'amount_paid': 0,
              'due_date': '2026-10-28',
              'waiver_amount': 530,
              'external_paid': 0,
              'settlement_state': 'settled',
              'collection_cutoff_at': '2026-10-28T04:00:00Z',
              'waiver_assignment_id': 'assignment',
              'waived_at': '2026-10-02T04:00:00Z',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final repo = BillRepositoryImpl(db, client);
    final online = await repo.historyFor(const ConsumerId('household'));
    expect(online, isA<Ok<List<Bill>>>());
    offline = true;
    final saved = await repo.historyFor(const ConsumerId('household'));
    final bill = (saved as Ok<List<Bill>>).value.single;
    expect(bill.isWaived, isTrue);
    expect(bill.settlementState, 'settled');
    expect(bill.collectionCutoffAt, DateTime.utc(2026, 10, 28, 4));
    expect(bill.amountPaid.isZero, isTrue);
    expect(bill.balance.isZero, isTrue);
    expect(bill.waiverAssignmentId, 'assignment');
    final detail = await repo.byId(const BillId('bill'));
    expect((detail as Ok<Bill?>).value!.isWaived, isTrue);
    final current = await repo.currentBillFor(const ConsumerId('household'));
    expect((current as Ok<Bill?>).value, isNull);
  });
  test(
    'verified direct payment and cutoff survive offline history and details',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var offline = false;
      final client = SupabaseClient(
        'https://waiver.test',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
        httpClient: MockClient((request) async {
          if (offline) throw const SocketException('offline');
          expect(
            request.url.queryParameters['select'],
            contains('waiver_amount'),
          );
          return http.Response(
            jsonEncode([
              {
                'bill_id': 'bill',
                'bill_no': 'B-1',
                'consumer_id': 'household',
                'cycle_year': 2026,
                'cycle_month': 10,
                'consumption': 10,
                'total_amount': 530,
                'amount_paid': 0,
                'due_date': '2026-10-28',
                'waiver_amount': 0,
                'external_paid': 530,
                'settlement_state': 'settled',
                'collection_cutoff_at': '2026-10-28T04:00:00Z',
                'waiver_assignment_id': 'assignment',
                'waived_at': '2026-10-02T04:00:00Z',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = BillRepositoryImpl(db, client);
      final online = await repo.historyFor(const ConsumerId('household'));
      expect(online, isA<Ok<List<Bill>>>());
      offline = true;
      final saved = await repo.historyFor(const ConsumerId('household'));
      final bill = (saved as Ok<List<Bill>>).value.single;
      expect(bill.isWaived, isFalse);
      expect(bill.externalPaid.centavos, 53000);
      expect(bill.settlementState, 'settled');
      expect(bill.collectionCutoffAt, DateTime.utc(2026, 10, 28, 4));
      expect(bill.amountPaid.isZero, isTrue);
      expect(bill.balance.isZero, isTrue);
      expect(bill.waiverAssignmentId, 'assignment');
      final detail = await repo.byId(const BillId('bill'));
      expect((detail as Ok<Bill?>).value!.externalPaid.centavos, 53000);
      final current = await repo.currentBillFor(const ConsumerId('household'));
      expect((current as Ok<Bill?>).value, isNull);
    },
  );
}
