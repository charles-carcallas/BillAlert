import 'dart:convert';

import 'package:billalert/core/errors/app_failure.dart';
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

/// A server that has not run `15_bill_meter_readings.sql` answers 42703 to
/// any select naming the reading columns, and answers normally without them.
///
/// This is the state a phone is in between an app update and the migration
/// reaching the database — which is exactly the window a household opened
/// History in and was told the server was broken.
void main() {
  const consumerId = ConsumerId('consumer-virgilio');
  late AppDatabase database;

  final List<String> selectsSeen = <String>[];

  http.Response ok(http.Request request, Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: const <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'content-range': '0-0/1',
    },
    request: request,
  );

  SupabaseClient serverWithout(String missingColumn) => SupabaseClient(
    'https://unmigrated.test',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    httpClient: MockClient((http.Request request) async {
      final String select = request.url.queryParameters['select'] ?? '';
      selectsSeen.add(select);
      if (select.contains(missingColumn)) {
        return http.Response(
          jsonEncode(<String, Object?>{
            'code': '42703',
            'details': null,
            'hint': null,
            'message': 'column v_bill_status.$missingColumn does not exist',
          }),
          400,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
          request: request,
        );
      }
      return ok(request, <Object>[
        <String, Object?>{
          'bill_id': 'bill-august',
          'bill_no': 'BA-202608-000001',
          'consumer_id': consumerId.value,
          'cycle_year': 2026,
          'cycle_month': 8,
          'consumption': '67.00',
          'total_amount': '1005.00',
          'due_date': '2026-09-30',
          'amount_paid': '0.00',
        },
      ]);
    }),
  );

  setUp(() {
    selectsSeen.clear();
    BillRepositoryImpl.resetSchemaProbe();
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('History loads from a server that has not run migration 15', () async {
    final client = serverWithout('previous_reading');
    final bills = BillRepositoryImpl(database, client);

    final result = await bills.historyFor(consumerId);

    expect(result, isA<Ok<List<Bill>>>());
    final List<Bill> history = (result as Ok<List<Bill>>).value;
    expect(history, hasLength(1));

    // The screen shows the bill, and says the readings are not there rather
    // than inventing a zero for them.
    expect(history.single.consumption.format(), '67.00 kWh');
    expect(history.single.previousReading, isNull);
    expect(history.single.hasMeterReadings, isFalse);

    // It asked for them once, was refused, and asked again without them.
    expect(selectsSeen, hasLength(2));
    expect(selectsSeen.first, contains('previous_reading'));
    expect(selectsSeen.last, isNot(contains('previous_reading')));

    await client.dispose();
  });

  test('the missing columns are asked for only once per run', () async {
    final client = serverWithout('previous_reading');
    final bills = BillRepositoryImpl(database, client);

    await bills.historyFor(consumerId);
    selectsSeen.clear();
    await bills.payableFor(consumerId);

    // The second query goes straight to the columns that exist: a household
    // does not pay for the discovery twice.
    expect(selectsSeen, hasLength(1));
    expect(selectsSeen.single, isNot(contains('previous_reading')));

    await client.dispose();
  });

  test('a real server error is not retried into a half-filled bill', () async {
    final client = SupabaseClient(
      'https://broken.test',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      httpClient: MockClient((http.Request request) async {
        selectsSeen.add(request.url.queryParameters['select'] ?? '');
        return http.Response(
          jsonEncode(<String, Object?>{
            'code': '42P01',
            'details': null,
            'hint': null,
            'message': 'relation "v_bill_status" does not exist',
          }),
          400,
          headers: const <String, String>{
            'content-type': 'application/json; charset=utf-8',
          },
          request: request,
        );
      }),
    );
    final bills = BillRepositoryImpl(database, client);

    final result = await bills.historyFor(consumerId);

    expect(result, isA<Err<List<Bill>>>());
    expect((result as Err<List<Bill>>).failure, isA<ServerFailure>());
    expect(selectsSeen, hasLength(1));

    await client.dispose();
  });
}
