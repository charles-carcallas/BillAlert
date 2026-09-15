import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/managed_account.dart';
import 'package:billalert/domain/usecases/admin/reset_account_password.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  const ManagedAccount reader = ManagedAccount(
    id: ProfileId('reader-1'),
    firstName: 'Ledesman',
    lastName: 'Dormal',
    kind: ManagedAccountKind.meterReader,
    reference: 'ledesman.dormal',
  );

  late FakeAuthRepository auth;
  late ResetAccountPassword reset;

  setUp(() {
    auth = FakeAuthRepository();
    reset = ResetAccountPassword(
      auth: auth,
      newTemporaryPassword: () => 'BillAlert0042',
    );
  });

  test('a new temporary password is made, sent, and returned once', () async {
    final result = await reset(account: reader);

    expect(auth.resetCalls, 1);
    expect(auth.resetAccount?.id.value, 'reader-1');
    expect(auth.resetTemporaryPassword, 'BillAlert0042');
    expect((result as Ok<String>).value, 'BillAlert0042');
  });

  test("the server's refusal reaches the caller, with no password", () async {
    auth.nextResetFailure = const PermissionFailure(
      'That account is not in your service area.',
    );

    final result = await reset(account: reader);

    expect(
      (result as Err<String>).failure.message,
      'That account is not in your service area.',
    );
  });
}
