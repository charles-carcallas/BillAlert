import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/household_login.dart';
import 'package:billalert/domain/usecases/admin/create_household_login.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

/// MTR-04: an Area President gives a household a sign-in.
void main() {
  const HouseholdWithoutLogin lorna = HouseholdWithoutLogin(
    id: ConsumerId('consumer-lorna'),
    consumerNo: ConsumerNumber('2026-1204-TUB'),
    firstName: 'Lorna',
    lastName: 'Caberte',
    purok: 'Purok 3',
  );

  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository());

  Future<Result<CreatedHouseholdLogin>> create({
    String username = 'lorna.caberte',
  }) => CreateHouseholdLogin(
    auth: auth,
    newTemporaryPassword: () => 'BillAlert0042',
  )(household: lorna, username: username);

  String messageOf(Result<CreatedHouseholdLogin> result) => switch (result) {
    Err(:final failure) => failure.message,
    Ok() => fail('expected the sign-in to be refused'),
  };

  test('the username is trimmed and lowercased before it is sent', () async {
    final result = await create(username: ' Lorna.Caberte ');

    expect(result, isA<Ok<CreatedHouseholdLogin>>());
    expect(auth.createLoginCalls, 1);
    expect(auth.createdLoginUsername, 'lorna.caberte');
    expect(auth.createdLoginHousehold?.id.value, 'consumer-lorna');
  });

  test('makes the temporary password itself and returns it once', () async {
    final result = await create();

    expect(auth.createdLoginPassword, 'BillAlert0042');
    expect(
      (result as Ok<CreatedHouseholdLogin>).value.temporaryPassword,
      'BillAlert0042',
    );
  });

  test('a malformed username never reaches the server', () async {
    expect(messageOf(await create(username: '2026lorna')), contains('letter'));
    expect(messageOf(await create(username: 'lo')), contains('3 to 50'));
    expect(auth.createLoginCalls, 0);
  });

  test("the server's refusal reaches the caller unchanged", () async {
    auth.nextCreateLoginFailure = const ConflictFailure(
      'This household already has a sign-in.',
    );

    final result = await create();

    expect(messageOf(result), 'This household already has a sign-in.');
  });

  group('the suggested username', () {
    HouseholdWithoutLogin named(String first, String last) =>
        HouseholdWithoutLogin(
          id: const ConsumerId('c'),
          consumerNo: const ConsumerNumber('2026-0001-TUB'),
          firstName: first,
          lastName: last,
        );

    test('is the first and last name joined with a dot', () {
      expect(lorna.suggestedUsername, 'lorna.caberte');
    });

    test('drops spaces inside a name and spells ñ as n', () {
      expect(
        named('Ma. Luisa', 'Dela Cruz').suggestedUsername,
        'ma.luisa.delacruz',
      );
      expect(named('Maria', 'Cañete').suggestedUsername, 'maria.canete');
    });

    test('is empty when the name cannot make a valid username', () {
      expect(named('', '').suggestedUsername, '');
      expect(named('1', '2').suggestedUsername, '');
    });
  });
}
