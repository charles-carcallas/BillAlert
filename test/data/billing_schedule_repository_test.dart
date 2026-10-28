import 'dart:convert';
import 'dart:io';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/billing_schedule_repository.dart';
import 'package:billalert/domain/entities/billing_schedule.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'confirmed schedule save survives offline reload under its owner scope',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      var offline = false;
      var day = 28;
      final client = SupabaseClient(
        'https://schedule.test',
        'key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
        httpClient: MockClient((request) async {
          if (offline) throw const SocketException('offline');
          if (request.url.path.endsWith('fn_save_billing_schedule')) {
            final body = jsonDecode(request.body) as Map;
            expect(body['p_expected_version'], 'v1');
            day = body['p_due_day'] as int;
          }
          return http.Response(
            jsonEncode({
              'version': day == 28 ? 'v1' : 'v2',
              'due_day': day,
              'cutoff_day': 28,
              'cutoff_minutes': 720,
              'effective_month': '2026-11-01',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final repo = BillingScheduleRepository(client, db);
      expect((await repo.load('admin')).dueDay, 28);
      await repo.save(
        const BillingSchedule(dueDay: 25, version: 'v1'),
        'retry',
        scope: 'admin',
      );
      offline = true;
      expect((await repo.load('admin')).dueDay, 25);
      await expectLater(repo.load('other'), throwsA(isA<SocketException>()));
    },
  );
}
