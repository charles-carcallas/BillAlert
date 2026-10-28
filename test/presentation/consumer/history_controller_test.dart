import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/repositories/payment_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/consumer/history_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';
import 'payment_history_filter_test.dart' show payment;

class _Payments implements PaymentRepository {
  Result<List<PaymentSummary>> result = Ok([
    payment('old', DateTime.utc(2026, 10, 1)),
    payment('new', DateTime.utc(2026, 10, 2)),
  ]);
  @override
  Future<Result<List<PaymentSummary>>> historyFor(ConsumerId id) async =>
      result;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'retains each transaction and reports refresh failure without losing receipts',
    () async {
      final payments = _Payments();
      final consumers = FakeConsumerRepository([])
        ..me = const Consumer(
          id: ConsumerId('home'),
          consumerNo: ConsumerNumber('H-1'),
          firstName: 'Test',
          lastName: 'Household',
          areaId: AreaId('area'),
          accountStatus: AccountStatus.active,
          previousReading: Kwh.zero,
        );
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(
              signedInUser: const ConsumerUser(
                id: ProfileId('user'),
                username: 'test',
                firstName: 'Test',
                lastName: 'User',
                mustChangePassword: false,
              ),
            ),
          ),
          consumerRepositoryProvider.overrideWithValue(consumers),
          billRepositoryProvider.overrideWithValue(FakeBillRepository()),
          paymentRepositoryProvider.overrideWithValue(payments),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final sub = container.listen(historyControllerProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(historyControllerProvider.notifier).load();
      expect(container.read(historyControllerProvider).receipts, hasLength(2));
      payments.result = const Err(NetworkFailure('No connection.'));
      await container.read(historyControllerProvider.notifier).load();
      final state = container.read(historyControllerProvider);
      expect(state.receipts.map((r) => r.receiptNo), ['old', 'new']);
      expect(state.failure, isA<NetworkFailure>());
      payments.result = const Ok([]);
      await container.read(historyControllerProvider.notifier).load();
      expect(container.read(historyControllerProvider).receipts, isEmpty);
      expect(container.read(historyControllerProvider).failure, isNull);
    },
  );
}
