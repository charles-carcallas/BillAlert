import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/outbox_repository_impl.dart';
import 'package:billalert/data/sync/outbox_session.dart';
import 'package:billalert/data/sync/sync_service.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/admin/post_bill_amount_controller.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

class _Link implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];
  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _Gateway implements OutboxGateway {
  final bool accepted;
  _Gateway(this.accepted);
  @override
  Future<Result<String>> submitPostedAmount(PostAmountOperation op) async =>
      accepted
      ? const Ok('notification-for-this-post')
      : const Err(NetworkFailure());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const user = AdminUser(
    id: ProfileId('admin'),
    username: 'test',
    firstName: 'Test',
    lastName: 'Admin',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  const entry = AwaitingAmountEntry(
    bill: Bill(
      id: BillId('bill'),
      billNo: BillNumber('TEST'),
      consumerId: ConsumerId('house'),
      cycle: CycleLabel(2026, 10),
      consumption: Kwh.fromHundredths(100),
      totalAmount: null,
      dueDate: null,
    ),
    consumerName: 'Test household',
    consumerNo: ConsumerNumber('TEST-HOUSE'),
    previousReading: Kwh.fromHundredths(0),
    currentReading: Kwh.fromHundredths(100),
    readingDate: PhDate(2026, 10, 2),
    daysWaiting: 0,
  );
  for (final accepted in [true, false]) {
    test(
      'posting confirmation follows persisted operation status: accepted=$accepted',
      () async {
        final db = AppDatabase.forTesting(NativeDatabase.memory());
        final session = OutboxSession()..bind(user);
        final outbox = OutboxRepositoryImpl(db, session: session);
        final sync = SyncService(
          outbox,
          _Gateway(accepted),
          connectivity: _Link(),
          session: session,
        );
        final bills = FakeBillRepository()..queue = [entry];
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(
              () => FakeAuthController(signedInUser: user),
            ),
            outboxRepositoryProvider.overrideWithValue(outbox),
            syncServiceProvider.overrideWithValue(sync),
            billRepositoryProvider.overrideWithValue(bills),
            phClockProvider.overrideWithValue(
              FixedPhClock.onPhDate(const PhDate(2026, 10, 2)),
            ),
          ],
        );
        await container.read(authControllerProvider.future);
        final controller = container.read(
          postBillAmountControllerProvider.notifier,
        );
        await controller.refresh();
        await controller.post(
          entry: entry,
          amountText: '99.40',
          dueDate: const PhDate(2026, 10, 28),
        );
        final state = container.read(postBillAmountControllerProvider);
        final saved =
            (await outbox.all() as Ok<List<OutboxEntry>>).value.single;
        expect(
          saved.status,
          accepted ? OutboxStatus.synced : OutboxStatus.failed,
        );
        expect(
          state.postedMessage,
          contains(accepted ? 'posted for' : 'waiting to sync'),
        );
        expect(
          state.queue,
          isEmpty,
          reason:
              'Stale server cache cannot make an already captured bill actionable',
        );
        container.dispose();
        await sync.dispose();
        await db.close();
      },
    );
  }
}
