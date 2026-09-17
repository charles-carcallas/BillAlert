import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/entities/household_login.dart';
import 'package:billalert/domain/entities/managed_account.dart';
import 'package:billalert/domain/entities/staff_account.dart';
import 'package:billalert/domain/usecases/admin/create_consumer.dart';
import 'package:billalert/domain/usecases/admin/create_household_login.dart';
import 'package:billalert/domain/usecases/admin/create_staff_account.dart';
import 'package:billalert/domain/usecases/admin/reset_account_password.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// The Area President's account work with no signal.
///
/// None of it waits to sync: the server has to check the details and make the
/// login. So offline, the message must say nothing happened. The app's general
/// offline message promises the work will sync, and an Area President who
/// believed it would hand over a temporary password for an account that does
/// not exist.
void main() {
  AppFailure failureOf<T>(Result<T> result) => switch (result) {
    Err(:final failure) => failure,
    Ok() => fail('expected no signal to refuse this'),
  };

  void expectNothingHappened(AppFailure failure, String saying) {
    expect(failure, isA<NetworkFailure>());
    expect(failure.message, contains(saying));
    expect(failure.message, isNot(contains('sync')));
  }

  test('creating a staff account', () async {
    final FakeAuthRepository auth = FakeAuthRepository()
      ..nextCreateStaffFailure = const NetworkFailure();

    final result =
        await CreateStaffAccount(
          auth: auth,
          newTemporaryPassword: () => 'BillAlert0042',
        )(
          username: 'maria.canete',
          firstName: 'Maria',
          lastName: 'Cañete',
          contactNumber: '',
          role: StaffRole.cashier,
        );

    expectNothingHappened(failureOf(result), 'Nothing was created');
  });

  test('giving a household a sign-in', () async {
    final FakeAuthRepository auth = FakeAuthRepository()
      ..nextCreateLoginFailure = const NetworkFailure();

    final result =
        await CreateHouseholdLogin(
          auth: auth,
          newTemporaryPassword: () => 'BillAlert0042',
        )(
          household: const HouseholdWithoutLogin(
            id: ConsumerId('consumer-lorna'),
            consumerNo: ConsumerNumber('2026-1204-TUB'),
            firstName: 'Lorna',
            lastName: 'Caberte',
            purok: 'Purok 3',
          ),
          username: 'lorna.caberte',
        );

    expectNothingHappened(failureOf(result), 'Nothing was created');
  });

  test('resetting a password', () async {
    final FakeAuthRepository auth = FakeAuthRepository()
      ..nextResetFailure = const NetworkFailure();

    final result =
        await ResetAccountPassword(
          auth: auth,
          newTemporaryPassword: () => 'BillAlert0042',
        )(
          account: const ManagedAccount(
            id: ProfileId('reader-1'),
            firstName: 'Ledesman',
            lastName: 'Dormal',
            kind: ManagedAccountKind.meterReader,
            reference: 'ledesman.dormal',
          ),
        );

    expectNothingHappened(failureOf(result), 'was not changed');
  });

  test('adding a household', () async {
    final FakeConsumerRepository consumers = FakeConsumerRepository(
      <Consumer>[],
    )..createFailure = const NetworkFailure();

    final result = await CreateConsumer(consumers: consumers)(
      consumerNo: '2026-1205-TUB',
      firstName: 'Lorna',
      lastName: 'Caberte',
      contactNumber: '',
      purok: 'Purok 3',
      meterSerialNo: '',
      areaId: const AreaId('area-3'),
      createdBy: const ProfileId('admin-1'),
    );

    expectNothingHappened(failureOf(result), 'Nothing was saved');
  });

  test('a refusal other than no signal is left as the server said it', () {
    const Result<void> refused = Err<void>(
      ConflictFailure('That username is already taken.'),
    );

    expect(
      failureOf(refused.ifOffline('Nothing was created.')).message,
      'That username is already taken.',
    );
  });
}
