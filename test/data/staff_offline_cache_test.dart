import 'dart:convert';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/bill_repository_impl.dart';
import 'package:billalert/data/repositories/notice_repository_impl.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/repositories/notice_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Admin's and Cashier's lists open with no signal, from the last answer
/// the server gave, and a real server refusal is never hidden behind it.
void main() {
  const AreaId area = AreaId('area-3');
  late AppDatabase database;

  /// [mode] is 'online', 'offline' or 'refused'.
  SupabaseClient server(Object rows, String Function() mode) => SupabaseClient(
    'https://billalert.test',
    'anon-key',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    httpClient: MockClient((http.Request request) async {
      switch (mode()) {
        case 'offline':
          throw http.ClientException('Connection failed', request.url);
        case 'refused':
          return http.Response(
            jsonEncode(<String, Object?>{
              'code': '42501',
              'details': null,
              'hint': null,
              'message': 'permission denied for view v_consumer_outstanding',
            }),
            403,
            headers: const <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
            request: request,
          );
      }
      return http.Response(
        jsonEncode(rows),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
        },
        request: request,
      );
    }),
  );

  final outstandingRow = <String, Object?>{
    'consumer_id': 'consumer-1',
    'consumer_no': '2020-0791-TUB',
    'consumer_name': 'Bienvenido Sarigumba',
    'purok': 'Purok 3',
    'area_id': area.value,
    'unpaid_bill_count': 1,
    'total_outstanding': '671.00',
    'oldest_due_date': '2026-09-28',
    'overdue_bill_count': 0,
  };

  setUp(() {
    BillRepositoryImpl.resetSchemaProbe();
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test(
    'the Cashier consumer list opens offline from its last answer',
    () async {
      var mode = 'online';
      final client = server(<Object>[outstandingRow], () => mode);
      final bills = BillRepositoryImpl(database, client);

      final online = await bills.outstandingInArea(area);
      expect(online, isA<Ok<List<ConsumerOutstanding>>>());

      mode = 'offline';
      final offline = await bills.outstandingInArea(area);

      expect(
        (offline as Ok<List<ConsumerOutstanding>>).value.single.consumerName,
        'Bienvenido Sarigumba',
      );
      await client.dispose();
    },
  );

  test('never loaded and offline still says there is no connection', () async {
    final client = server(<Object>[], () => 'offline');
    final bills = BillRepositoryImpl(database, client);

    final result = await bills.outstandingInArea(area);

    expect(
      (result as Err<List<ConsumerOutstanding>>).failure,
      isA<NetworkFailure>(),
    );
    await client.dispose();
  });

  test('a refusal from the server is not hidden by a saved copy', () async {
    var mode = 'online';
    final client = server(<Object>[outstandingRow], () => mode);
    final bills = BillRepositoryImpl(database, client);

    await bills.outstandingInArea(area);
    mode = 'refused';
    final result = await bills.outstandingInArea(area);

    expect(result, isA<Err<List<ConsumerOutstanding>>>());
    await client.dispose();
  });

  test('signing out forgets the saved staff lists', () async {
    var mode = 'online';
    final client = server(<Object>[outstandingRow], () => mode);
    final bills = BillRepositoryImpl(database, client);

    await bills.outstandingInArea(area);
    await database.clearCachedData();
    mode = 'offline';
    final result = await bills.outstandingInArea(area);

    expect(result, isA<Err<List<ConsumerOutstanding>>>());
    await client.dispose();
  });

  test('the Admin notice list opens offline too', () async {
    var mode = 'online';
    final client = server(<Object>[], () => mode);
    final notices = NoticeRepositoryImpl(database, client);

    await notices.activeFor(area);
    mode = 'offline';
    final result = await notices.activeFor(area);

    expect(result, isA<Ok<List<ActiveNotice>>>());
    await client.dispose();
  });
}
