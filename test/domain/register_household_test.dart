import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/usecases/admin/create_consumer.dart';
import 'package:billalert/domain/usecases/admin/create_household_login.dart';
import 'package:billalert/domain/usecases/admin/register_household.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// ADM-03 + MTR-04: registering a household gives it its sign-in too.
void main() {
  late FakeConsumerRepository consumers;
  late FakeAuthRepository auth;
  late RegisterHousehold register;

  setUp(() {
    consumers = FakeConsumerRepository(<Consumer>[]);
    auth = FakeAuthRepository();
    register = RegisterHousehold(
      createConsumer: CreateConsumer(consumers: consumers),
      createLogin: CreateHouseholdLogin(
        auth: auth,
        newTemporaryPassword: () => 'BillAlert0042',
      ),
    );
  });

  Future<Result<RegisteredHousehold>> run({
    String consumerNo = '2026-1234-TUB',
    String firstName = 'Lorna',
    String lastName = 'Caberte',
    String username = 'lorna.caberte',
  }) => register(
    consumerNo: consumerNo,
    firstName: firstName,
    lastName: lastName,
    contactNumber: '',
    purok: 'Purok 3',
    meterSerialNo: 'BIEC-08399',
    username: username,
    areaId: const AreaId('area-3'),
    createdBy: const ProfileId('admin-1'),
  );

  test('creates the household, then the sign-in for that household', () async {
    final result = await run();

    final RegisteredHousehold registered =
        (result as Ok<RegisteredHousehold>).value;
    expect(consumers.createCount, 1);
    expect(auth.createLoginCalls, 1);
    // The sign-in is linked to the household just saved, not to anything
    // the form sent.
    expect(auth.createdLoginHousehold?.id.value, 'created-consumer');
    expect(auth.createdLoginUsername, 'lorna.caberte');
    expect(registered.household.fullName, 'Lorna Caberte');
    expect(registered.login?.temporaryPassword, 'BillAlert0042');
    expect(registered.loginFailure, isNull);
  });

  test(
    'a malformed username creates nothing, not even the household',
    () async {
      final result = await run(username: '2026lorna');

      expect(
        (result as Err<RegisteredHousehold>).failure,
        isA<ValidationFailure>(),
      );
      expect(consumers.createCount, 0);
      expect(auth.createLoginCalls, 0);
    },
  );

  test('missing household details are reported before the username', () async {
    final result = await run(consumerNo: '  ', username: '2026lorna');

    expect(
      (result as Err<RegisteredHousehold>).failure.message,
      contains('consumer number'),
    );
    expect(consumers.createCount, 0);
  });

  test('a refused sign-in keeps the household and says why', () async {
    auth.nextCreateLoginFailure = const ConflictFailure(
      'Username lorna.caberte is already taken.',
    );

    final result = await run();

    final RegisteredHousehold registered =
        (result as Ok<RegisteredHousehold>).value;
    expect(consumers.createCount, 1);
    expect(registered.household.fullName, 'Lorna Caberte');
    expect(registered.login, isNull);
    expect(
      registered.loginFailure?.message,
      'Username lorna.caberte is already taken.',
    );
  });

  test('when the household cannot be saved, no sign-in is tried', () async {
    consumers.createFailure = const ConflictFailure(
      'Consumer number 2026-1234-TUB is already in use.',
    );

    final result = await run();

    expect(
      (result as Err<RegisteredHousehold>).failure.message,
      'Consumer number 2026-1234-TUB is already in use.',
    );
    expect(auth.createLoginCalls, 0);
  });
}
