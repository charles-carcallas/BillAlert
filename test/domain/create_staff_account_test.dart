import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/staff_account.dart';
import 'package:billalert/domain/usecases/admin/create_staff_account.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late CreateStaffAccount createStaff;

  setUp(() {
    auth = FakeAuthRepository();
    createStaff = CreateStaffAccount(auth: auth);
  });

  Future<Result<CreatedStaffAccount>> create({
    String username = 'rodrigo.balistoy',
    String firstName = 'Rodrigo',
    String lastName = 'Balistoy',
    String contactNumber = '0918 555 0233',
    StaffRole role = StaffRole.meterReader,
    String password = 'Temporary#42',
    String confirm = 'Temporary#42',
  }) => createStaff(
    username: username,
    firstName: firstName,
    lastName: lastName,
    contactNumber: contactNumber,
    role: role,
    temporaryPassword: password,
    confirmPassword: confirm,
  );

  test(
    'normalises only username and preserves mobile text for the trigger',
    () async {
      final result = await create(username: ' Rodrigo.Balistoy ');

      expect(result, isA<Ok<CreatedStaffAccount>>());
      expect(auth.createdStaffUsername, 'rodrigo.balistoy');
      expect(auth.createdStaffContactNumber, '0918 555 0233');
      expect(auth.createdStaffRole, StaffRole.meterReader);
    },
  );

  test('rejects a malformed username before calling the repository', () async {
    final result = await create(username: '42 invalid');

    expect(
      (result as Err<CreatedStaffAccount>).failure,
      isA<ValidationFailure>(),
    );
    expect(auth.createStaffCalls, 0);
  });

  test('requires both names', () async {
    expect((await create(firstName: '')), isA<Err<CreatedStaffAccount>>());
    expect((await create(lastName: '')), isA<Err<CreatedStaffAccount>>());
    expect(auth.createStaffCalls, 0);
  });

  test('requires an eight-character matching temporary password', () async {
    final short = await create(password: 'short', confirm: 'short');
    final mismatch = await create(confirm: 'Different#42');

    expect(
      (short as Err<CreatedStaffAccount>).failure,
      isA<ValidationFailure>(),
    );
    expect(
      (mismatch as Err<CreatedStaffAccount>).failure,
      isA<ValidationFailure>(),
    );
    expect(auth.createStaffCalls, 0);
  });

  test('blank mobile number becomes absent', () async {
    await create(contactNumber: '   ', role: StaffRole.cashier);

    expect(auth.createdStaffContactNumber, isNull);
    expect(auth.createdStaffRole, StaffRole.cashier);
  });
}
