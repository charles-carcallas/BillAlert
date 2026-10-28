import 'dart:convert';

import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/overdue_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'collection history filters terminal events and caches by owner and area',
    () async {
      var offline = false;
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          if (offline) throw http.ClientException('Network unreachable');
          expect(request.url.path, '/rest/v1/overdue_collection_audit');
          expect(
            request.url.queryParameters['bills.consumers.area_id'],
            'eq.area',
          );
          expect(
            request.url.queryParameters['action'],
            'in.("consumed","revoked")',
          );
          return http.Response(
            jsonEncode([
              {
                'action': 'consumed',
                'amount': '350',
                'occurred_at': '2026-10-03T12:00:00Z',
                'bills': {
                  'bill_no': 'SEPT',
                  'consumers': {
                    'first_name': 'Test',
                    'last_name': 'Household',
                    'consumer_no': 'TEST-1',
                    'area_id': 'area',
                  },
                },
              },
            ]),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(() async {
        await client.dispose();
        await db.close();
      });
      final repository = OverdueRepository(client, db);
      final online = await repository.history('area', 'admin');
      expect(online.single['action'], 'consumed');
      offline = true;
      expect(await repository.history('area', 'admin'), online);
      await expectLater(
        repository.history('area', 'other-owner'),
        throwsA(anything),
      );
    },
  );
}
