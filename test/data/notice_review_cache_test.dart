import 'dart:async';
import 'dart:convert';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/notice_repository_impl.dart';
import 'package:billalert/domain/repositories/notice_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> payload() => {
  'notice_id': 'notice',
  'notice_no': 'DN-TEST',
  'consumer_id': 'house',
  'consumer_name': 'Test household',
  'reason': 'Overdue',
  'served_at': '2026-10-02T00:00:00Z',
  'earliest_lawful_at': '2026-10-04T00:00:00Z',
  'notice_period_elapsed': false,
  'amount_overdue': 0,
  'ready_to_close': true,
  'status': 'active',
  'checked_at': '2026-10-02T01:00:00Z',
  'covered_bills': [
    {
      'bill_no': 'BILL',
      'cycle_label': 'September 2026',
      'due_date': '2026-09-28',
      'balance': 0,
      'amount_at_issue': 500,
      'legacy': false,
    },
  ],
  'overdue_bills': [],
  'receipts': [
    {
      'receipt_no': 'EXACT',
      'bill_no': 'BILL',
      'amount_paid': 500,
      'paid_at': '2026-10-02T01:00:00Z',
    },
  ],
  'sms': [
    {
      'status': 'sent',
      'dispatch_state': 'accepted',
      'sent_at': '2026-10-02T01:02:00Z',
    },
  ],
};

void main() {
  test(
    'saved review retains original amount, receipt, SMS and server-check time offline',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      var offline = false;
      final client = SupabaseClient(
        'https://billalert.test',
        'test-key',
        httpClient: MockClient((request) async {
          if (offline) throw http.ClientException('No connection');
          return http.Response(
            jsonEncode(payload()),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final repo = NoticeRepositoryImpl(db, client);
      expect(
        await repo.review(const NoticeId('notice')),
        isA<Ok<NoticeReview?>>(),
      );
      offline = true;
      final cached =
          (await repo.review(const NoticeId('notice')) as Ok<NoticeReview?>)
              .value!;
      expect(cached.coveredBills.single.amountAtIssue!.centavos, 50000);
      expect(cached.receipts.single.receiptNo, 'EXACT');
      expect(cached.sms.single.label, 'Sent by gateway');
      expect(cached.checkedAt, DateTime.utc(2026, 10, 2, 1));
      await db.clearCachedData();
      expect(
        await repo.review(const NoticeId('notice')),
        isA<Err<NoticeReview?>>(),
      );
      await db.close();
      await client.dispose();
    },
  );
  test(
    'late review response cannot refill a signed-out account cache',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final started = Completer<void>(), release = Completer<void>();
      final client = SupabaseClient(
        'https://billalert.test',
        'test-key',
        httpClient: MockClient((request) async {
          started.complete();
          await release.future;
          return http.Response(
            jsonEncode(payload()),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final request = NoticeRepositoryImpl(
        db,
        client,
      ).review(const NoticeId('notice'));
      await started.future;
      await db.clearCachedData();
      release.complete();
      expect(await request, isA<Err<NoticeReview?>>());
      expect(await db.select(db.cachedQueries).get(), isEmpty);
      await db.close();
      await client.dispose();
    },
  );
  test(
    'closed history includes actor and notes without reopening an active record',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final client = SupabaseClient(
        'https://billalert.test',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['area_id'], 'eq.area');
          return http.Response(
            jsonEncode([
              {
                'notice_id': 'notice',
                'notice_no': 'DN-TEST',
                'consumer_name': 'Test household',
                'status': 'cancelled',
                'closed_at': '2026-10-02T01:00:00Z',
                'closed_by_name': 'Test Admin',
                'outcome_notes': 'Wrong record',
              },
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final rows =
          (await NoticeRepositoryImpl(
                    db,
                    client,
                  ).historyFor(const AreaId('area'))
                  as Ok<List<ClosedNotice>>)
              .value;
      expect(rows.single.outcome, NoticeOutcome.cancelled);
      expect(rows.single.closedBy, 'Test Admin');
      expect(rows.single.notes, 'Wrong record');
      await db.close();
      await client.dispose();
    },
  );
}
