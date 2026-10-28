import 'dart:convert';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/bill_repository_impl.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  Map<String, dynamic> row(String id, int month, String? amount, String? due) =>
      {
        'consumer_id': id,
        'consumer_no': id,
        'first_name': id,
        'last_name': 'Test',
        'purok': null,
        'cycle_year': 2026,
        'cycle_month': month,
        'total_amount': amount,
        'balance': amount ?? '0.00',
        'due_date': due,
      };
  test(
    'Current excludes overdue households and restores them after debt is paid',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      bool overduePaid = false;
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/v_bill_status');
          expect(request.url.queryParameters['area_id'], 'eq.area');
          expect(request.url.queryParameters['status'], 'not.in.(paid,waived)');
          return http.Response(
            jsonEncode([
              row('old-only', 9, '350.00', '2026-09-28'),
              if (!overduePaid) row('mixed', 9, '350.00', '2026-09-28'),
              row('mixed', 10, '250.00', '2026-10-28'),
              row('current', 10, '175.00', '2026-10-28'),
              row('unpriced', 10, null, null),
              row('old-unpriced', 9, null, null),
              row('future', 11, '100.00', '2026-11-28'),
              row('current-overdue', 10, '100.00', '2026-10-01'),
              row('due-today', 10, '50.00', '2026-10-03'),
            ]),
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-9/10',
            },
          );
        }),
      );
      addTearDown(() async {
        await client.dispose();
        await db.close();
      });
      final repo = BillRepositoryImpl(db, client);
      final result = await repo.currentCollectionsInArea(
        const AreaId('area'),
        const PhDate(2026, 10, 3),
      );
      final homes = (result as Ok<List<ConsumerOutstanding>>).value;
      expect(homes.map((h) => h.consumerId.value), [
        'current',
        'unpriced',
        'due-today',
      ]);
      expect(homes.first.totalOutstanding.centavos, 17500);
      expect(homes.first.payableBillCount, 1);
      expect(homes.first.overdueCount, 0);
      expect(homes[1].unpricedBillCount, 1);
      expect(homes.last.overdueCount, 0);
      expect(
        homes.fold<int>(0, (sum, h) => sum + h.totalOutstanding.centavos),
        22500,
      );

      overduePaid = true;
      final refreshed = await repo.currentCollectionsInArea(
        const AreaId('area'),
        const PhDate(2026, 10, 3),
      );
      final restored = (refreshed as Ok<List<ConsumerOutstanding>>).value;
      expect(restored.map((h) => h.consumerId.value), [
        'mixed',
        'current',
        'unpriced',
        'due-today',
      ]);
      expect(restored.first.overdueCount, 0);
      expect(restored.first.totalOutstanding.centavos, 25000);
    },
  );
  test(
    'cached main list rechecks due dates as the day changes offline',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      bool offline = false;
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          if (offline) throw http.ClientException('Network unreachable');
          return http.Response(
            jsonEncode([row('current', 10, '250.00', '2026-10-03')]),
            200,
            request: request,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-9/10',
            },
          );
        }),
      );
      addTearDown(() async {
        await client.dispose();
        await db.close();
      });
      final repo = BillRepositoryImpl(db, client);
      final initial = await repo.currentCollectionsInArea(
        const AreaId('area'),
        const PhDate(2026, 10, 3),
      );
      expect((initial as Ok<List<ConsumerOutstanding>>).value, hasLength(1));
      offline = true;
      final next = await repo.currentCollectionsInArea(
        const AreaId('area'),
        const PhDate(2026, 10, 4),
      );
      expect((next as Ok<List<ConsumerOutstanding>>).value, isEmpty);
    },
  );
}
