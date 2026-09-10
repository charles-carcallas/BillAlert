import 'package:billalert/core/config/app_config.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/demo/demo_environment.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/repositories/notice_repository.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/main.dart' as application;
import 'package:billalert/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo mode is off unless the build explicitly asked for it', () {
    // AppConfig.demoMode is a COMPILE-TIME constant, so its value depends on
    // how this test run itself was compiled. Asserting `isFalse` outright
    // meant the test failed whenever it was launched from the "BillAlert
    // (demo data)" configuration, which passes --dart-define=DEMO_MODE=true
    // to everything it builds — a red failure that said nothing about the
    // app.
    //
    // Comparing against the same environment value pins the two things that
    // can actually break: the key name, and the default. A typo in
    // AppConfig — reading DEMOMODE, say — makes these two disagree the
    // moment the define is set, so this is at its strongest under exactly
    // the configuration that used to break it.
    const bool askedFor = bool.fromEnvironment('DEMO_MODE');
    expect(AppConfig.demoMode, askedFor);
    expect(application.main, isNotNull);
  });

  test(
    'demo overrides provide repeatable data and isolated mutations',
    () async {
      final container = ProviderContainer(overrides: demoProviderOverrides());
      addTearDown(container.dispose);

      final auth = await container
          .read(authRepositoryProvider)
          .signIn(username: 'reader', password: 'demo');
      expect(auth, isA<Ok<AppUser>>());
      expect((auth as Ok<AppUser>).value, isA<MeterReaderUser>());

      final roster = await container
          .read(consumerRepositoryProvider)
          .areaRoster(const AreaId('demo-tubod-area'));
      expect(roster, isA<Ok<List<Consumer>>>());
      final consumers = (roster as Ok<List<Consumer>>).value;
      expect(consumers, hasLength(5));

      final consumer = consumers.first;
      final recorded = await container.read(recordMeterReadingProvider)(
        consumer: consumer,
        currentReading: const Kwh.fromHundredths(461100),
      );
      expect(recorded, isA<Ok>());
      final pending = await container.read(outboxRepositoryProvider).pending();
      expect((pending as Ok<List<OutboxEntry>>).value, hasLength(1));

      const noticeId = NoticeId('fe59ec52-60de-4663-b301-01a7861ae213');
      final notices = container.read(noticeRepositoryProvider);
      final beforeClose = await notices.byId(noticeId);
      expect((beforeClose as Ok<ActiveNotice?>).value, isNotNull);
      await notices.closeNotice(
        noticeId: noticeId,
        outcome: NoticeOutcome.cancelled,
        notes: 'Demo only',
      );
      final afterClose = await notices.byId(noticeId);
      expect((afterClose as Ok<ActiveNotice?>).value, isNull);
    },
  );

  test(
    'consumer demo history opens a receipt covering settled months',
    () async {
      final container = ProviderContainer(overrides: demoProviderOverrides());
      addTearDown(container.dispose);

      const consumerId = ConsumerId('demo-elena');
      final billResult = await container
          .read(billRepositoryProvider)
          .historyFor(consumerId);
      final paymentResult = await container
          .read(paymentRepositoryProvider)
          .historyFor(consumerId);

      final bills = (billResult as Ok<List<Bill>>).value;
      final receipts = (paymentResult as Ok<List<PaymentSummary>>).value;
      expect(receipts, hasLength(1));
      expect(receipts.single.receiptNo, 'OR-2026-0802-0018');
      expect(receipts.single.bills, hasLength(2));
      expect(
        bills.map((bill) => bill.id),
        containsAll(receipts.single.bills.map((bill) => bill.billId)),
      );
      expect(bills.where((bill) => bill.isSettled), hasLength(2));
    },
  );
}
