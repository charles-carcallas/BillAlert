import 'dart:convert';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/bill_repository_impl.dart';
import 'package:billalert/data/repositories/payment_repository_impl.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Meter Reader's remittance and reading sheet are opened at the BOHECO
/// office and on the round, both places without signal. Whatever was last
/// loaded online has to still be there.
void main() {
  const AreaId area = AreaId('area-3');
  late AppDatabase database;

  /// A server that answers with [rows] while [online] is true and drops the
  /// connection otherwise.
  SupabaseClient server(List<Object> Function() rows, bool Function() online) =>
      SupabaseClient(
        'https://billalert.test',
        'anon-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
        httpClient: MockClient((http.Request request) async {
          if (!online()) {
            throw http.ClientException('Connection failed', request.url);
          }
          return http.Response(
            jsonEncode(rows()),
            200,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
            request: request,
          );
        }),
      );

  setUp(() {
    BillRepositoryImpl.resetSchemaProbe();
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  group('remittance', () {
    // 29 Aug – 28 Sep 2026 in Manila.
    final DateTime from = DateTime.utc(2026, 8, 28, 16);
    final DateTime until = DateTime.utc(2026, 9, 28, 16);

    Map<String, Object?> paymentRow(String id, String paidAt, String amount) =>
        <String, Object?>{
          'payment_id': 'pay-$id',
          'consumer_id': 'consumer-$id',
          'bill_id': 'bill-$id',
          'bill_no': 'BA-$id',
          'cycle_label': 'September 2026',
          'receipt_no': 'OR-$id',
          'verification_code': 'V-$id',
          'amount_paid': amount,
          'transaction_total': amount,
          'cash_tendered': null,
          'change_due': null,
          'paid_at': paidAt,
          'cashier_id': 'cashier-1',
          'area_id': area.value,
          'consumer_name': 'Household $id',
        };

    test('what was loaded online is still there offline', () async {
      var online = true;
      final client = server(
        () => <Object>[
          paymentRow('1', '2026-09-09T02:30:00+00:00', '671.00'),
          paymentRow('2', '2026-09-08T02:30:00+00:00', '500.00'),
        ],
        () => online,
      );
      final payments = PaymentRepositoryImpl(database, client);

      await payments.collectedInArea(area, from: from, until: until);
      online = false;
      final result = await payments.collectedInArea(
        area,
        from: from,
        until: until,
      );

      final List<PaymentSummary> saved =
          (result as Ok<List<PaymentSummary>>).value;
      expect(saved.map((PaymentSummary p) => p.receiptNo), <String>[
        'OR-1',
        'OR-2',
      ]);
      expect(
        ((await payments.collectedInAreaSavedAt(area, from: from))
                as Ok<DateTime?>)
            .value,
        isNotNull,
      );
      await client.dispose();
    });

    test('a receipt the server stopped returning drops out of the saved '
        'total', () async {
      var rows = <Object>[
        paymentRow('1', '2026-09-09T02:30:00+00:00', '671.00'),
        paymentRow('2', '2026-09-08T02:30:00+00:00', '500.00'),
      ];
      var online = true;
      final client = server(() => rows, () => online);
      final payments = PaymentRepositoryImpl(database, client);

      await payments.collectedInArea(area, from: from, until: until);
      rows = <Object>[paymentRow('1', '2026-09-09T02:30:00+00:00', '671.00')];
      await payments.collectedInArea(area, from: from, until: until);
      online = false;
      final result = await payments.collectedInArea(
        area,
        from: from,
        until: until,
      );

      expect((result as Ok<List<PaymentSummary>>).value, hasLength(1));
      await client.dispose();
    });

    test('never loaded and offline says there is no connection', () async {
      final client = server(() => <Object>[], () => false);
      final payments = PaymentRepositoryImpl(database, client);

      final result = await payments.collectedInArea(
        area,
        from: from,
        until: until,
      );

      expect(
        (result as Err<List<PaymentSummary>>).failure,
        isA<NetworkFailure>(),
      );
      await client.dispose();
    });
  });

  group('reading sheet', () {
    const september = CycleLabel(2026, 9);

    test('readings loaded online are still there offline', () async {
      var online = true;
      final client = server(
        () => <Object>[
          <String, Object?>{
            'bill_id': 'bill-1',
            'bill_no': 'BA-202609-000001',
            'consumer_id': 'consumer-1',
            'cycle_year': 2026,
            'cycle_month': 9,
            'consumption': '58.00',
            'total_amount': null,
            'due_date': null,
            'amount_paid': '0.00',
            'previous_reading': '4610.00',
            'current_reading': '4668.00',
            'reading_date': '2026-09-07',
          },
        ],
        () => online,
      );
      final bills = BillRepositoryImpl(database, client);

      await bills.readingsForCycle(area, september);
      online = false;
      final result = await bills.readingsForCycle(area, september);

      final Bill saved = (result as Ok<List<Bill>>).value.single;
      expect(saved.currentReading?.format(), '4,668.00 kWh');
      expect(saved.previousReading?.format(), '4,610.00 kWh');
      await client.dispose();
    });
  });
}
