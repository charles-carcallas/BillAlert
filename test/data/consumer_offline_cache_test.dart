import 'dart:convert';
import 'dart:io';

import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/bill_repository_impl.dart';
import 'package:billalert/data/repositories/consumer_repository_impl.dart';
import 'package:billalert/data/repositories/notification_repository_impl.dart';
import 'package:billalert/data/repositories/payment_repository_impl.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/repositories/notification_repository.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  const consumerId = ConsumerId('consumer-virgilio');
  late AppDatabase database;
  late SupabaseClient online;
  late SupabaseClient offline;

  http.Response jsonResponse(http.Request request, Object value) =>
      http.Response(
        jsonEncode(value),
        200,
        headers: const <String, String>{
          'content-type': 'application/json; charset=utf-8',
          'content-range': '0-0/1',
        },
        request: request,
      );

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database
        .into(database.cacheOwner)
        .insert(
          CacheOwnerCompanion.insert(
            id: const Value<int>(1),
            profileId: 'profile-virgilio',
            username: const Value<String?>('virgilio.busalanan'),
            firstName: const Value<String?>('Virgilio'),
            lastName: const Value<String?>('Busalanan'),
            mustChangePassword: const Value<bool?>(false),
            role: 'consumer',
            cachedAt: '2026-09-15T00:00:00.000Z',
          ),
        );

    online = SupabaseClient(
      'https://cache.test',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      httpClient: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/consumers')) {
          return jsonResponse(request, <Map<String, Object?>>[
            <String, Object?>{
              'id': consumerId.value,
              'consumer_no': '2020-0714-TUB',
              'first_name': 'Virgilio',
              'last_name': 'Busalanan',
              'contact_number': '+639175550142',
              'meter_serial_no': 'MTR-003',
              'area_id': 'area-3',
              'purok': 'Purok 3',
              'account_status': 'active',
            },
          ]);
        }
        if (path.endsWith('/v_consumer_current_bill')) {
          return jsonResponse(request, <Map<String, Object?>>[
            <String, Object?>{
              'bill_id': 'bill-august',
              'bill_no': 'BA-202608-000001',
              'consumer_id': consumerId.value,
              'period_start': '2026-08-01',
              'consumption': '63.00',
              'total_amount': '1272.00',
              'amount_paid': '0.00',
              'due_date': '2026-09-25',
            },
          ]);
        }
        if (path.endsWith('/v_bill_status')) {
          return jsonResponse(request, <Map<String, Object?>>[
            <String, Object?>{
              'bill_id': 'bill-august',
              'bill_no': 'BA-202608-000001',
              'consumer_id': consumerId.value,
              'cycle_year': 2026,
              'cycle_month': 8,
              'consumption': '63.00',
              'total_amount': '1272.00',
              'amount_paid': '0.00',
              'due_date': '2026-09-25',
            },
            <String, Object?>{
              'bill_id': 'bill-july',
              'bill_no': 'BA-202607-000001',
              'consumer_id': consumerId.value,
              'cycle_year': 2026,
              'cycle_month': 7,
              'consumption': '60.00',
              'total_amount': '1200.00',
              'amount_paid': '1200.00',
              'due_date': '2026-08-25',
            },
          ]);
        }
        if (path.endsWith('/v_payment_history')) {
          return jsonResponse(request, <Map<String, Object?>>[
            <String, Object?>{
              'payment_id': 'payment-july',
              'consumer_id': consumerId.value,
              'bill_id': 'bill-july',
              'bill_no': 'BA-202607-000001',
              'cycle_label': 'July 2026',
              'receipt_no': 'BIEC-2026-09-004471',
              'consumer_name': 'Virgilio Busalanan',
              'verification_code': 'VERIFY471',
              'amount_paid': '1200.00',
              'transaction_total': '1200.00',
              'cash_tendered': '1500.00',
              'change_due': '300.00',
              'paid_at': '2026-09-10T02:00:00.000Z',
            },
          ]);
        }
        if (path.endsWith('/notifications')) {
          return jsonResponse(request, <Map<String, Object?>>[
            <String, Object?>{
              'id': 'notification-1',
              'consumer_id': consumerId.value,
              'notif_type': 'bill_ready',
              'channel': 'push',
              'message_content': 'Your August bill is ready.',
              'status': 'sent',
              'is_read': false,
              'created_at': '2026-09-10T01:00:00.000Z',
              'bill_id': 'bill-august',
              'disconnection_id': null,
              'failed_reason': null,
              'sent_at': '2026-09-10T01:05:00.000Z',
            },
            // The same bill as a text (14_bill_sms.sql).
            <String, Object?>{
              'id': 'notification-1-text',
              'consumer_id': consumerId.value,
              'notif_type': 'bill_ready',
              'channel': 'sms',
              'message_content': 'Your August bill is ready.',
              'status': 'sent',
              'is_read': true,
              'created_at': '2026-09-10T01:00:00.000Z',
              'bill_id': 'bill-august',
              'disconnection_id': null,
              'failed_reason': null,
              'sent_at': '2026-09-10T01:20:00.000Z',
            },
          ]);
        }
        return jsonResponse(request, const <Object>[]);
      }),
    );

    offline = SupabaseClient(
      'https://offline.invalid',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );
  });

  tearDown(() async {
    await database.close();
    await online.dispose();
    await offline.dispose();
  });

  test(
    'all Consumer read models survive an offline app restart',
    () async {
      final onlineConsumers = ConsumerRepositoryImpl(database, online);
      final onlineBills = BillRepositoryImpl(database, online);
      final onlinePayments = PaymentRepositoryImpl(database, online);
      final onlineNotifications = NotificationRepositoryImpl(database, online);

      expect(await onlineConsumers.signedInConsumer(), isA<Ok<Consumer?>>());
      expect(await onlineBills.currentBillFor(consumerId), isA<Ok<Bill?>>());
      expect(await onlineBills.historyFor(consumerId), isA<Ok<List<Bill>>>());
      expect(
        await onlinePayments.historyFor(consumerId),
        isA<Ok<List<PaymentSummary>>>(),
      );
      expect(
        await onlineNotifications.inboxFor(consumerId),
        isA<Ok<List<AppNotification>>>(),
      );

      // New repository instances stand in for Android killing and reopening
      // the process. Their Supabase transport is completely offline.
      final offlineConsumers = ConsumerRepositoryImpl(database, offline);
      final offlineBills = BillRepositoryImpl(database, offline);
      final offlinePayments = PaymentRepositoryImpl(database, offline);
      final offlineNotifications = NotificationRepositoryImpl(
        database,
        offline,
      );

      final consumer = await offlineConsumers.signedInConsumer();
      expect((consumer as Ok<Consumer?>).value?.fullName, 'Virgilio Busalanan');

      final current = await offlineBills.currentBillFor(consumerId);
      expect((current as Ok<Bill?>).value?.billNo.value, 'BA-202608-000001');

      final bills = await offlineBills.historyFor(consumerId);
      expect((bills as Ok<List<Bill>>).value, hasLength(2));

      final receipts = await offlinePayments.historyFor(consumerId);
      final receipt = (receipts as Ok<List<PaymentSummary>>).value.single;
      expect(receipt.receiptNo, 'BIEC-2026-09-004471');
      expect(receipt.verificationCode, 'VERIFY471');
      expect(receipt.bills.single.billNo.value, 'BA-202607-000001');

      // The bill's text copy is left out of the Inbox, online and offline.
      final alerts = await offlineNotifications.inboxFor(consumerId);
      final AppNotification alert =
          (alerts as Ok<List<AppNotification>>).value.single;
      expect(alert.channel, 'push');
      expect(alert.message, 'Your August bill is ready.');

      // What the Inbox details sheet shows, still there with no signal...
      expect(alert.billId?.value, 'bill-august');
      expect(alert.status, 'sent');
      expect(alert.sentAt, DateTime.utc(2026, 9, 10, 1, 5));

      // ...and the bill it points at opens from the cache.
      final opened = await offlineBills.byId(const BillId('bill-august'));
      expect((opened as Ok<Bill?>).value?.billNo.value, 'BA-202608-000001');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
