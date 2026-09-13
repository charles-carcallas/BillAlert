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

  setUp(() => auth = FakeAuthRepository());

  String messageOf(Result<void> result) => switch (result) {
    Err(:final failure) => failure.message,
    Ok() => fail('expected the reset to be refused'),
  };

  test(
    'a temporary password under 8 characters never reaches the server',
    () async {
      final result = await ResetAccountPassword(auth: auth)(
        account: reader,
        temporaryPassword: 'short',
        confirmPassword: 'short',
      );

      expect(messageOf(result), contains('at least 8'));
      expect(auth.resetCalls, 0);
    },
  );

  test('passwords that do not match never reach the server', () async {
    final result = await ResetAccountPassword(auth: auth)(
      account: reader,
      temporaryPassword: 'Temporary-2026',
      confirmPassword: 'Temporary-2025',
    );

    expect(messageOf(result), contains('do not match'));
    expect(auth.resetCalls, 0);
  });

  test('a valid temporary password is sent for the chosen account', () async {
    final result = await ResetAccountPassword(auth: auth)(
      account: reader,
      temporaryPassword: 'Temporary-2026',
      confirmPassword: 'Temporary-2026',
    );

    expect(result, isA<Ok<void>>());
    expect(auth.resetCalls, 1);
    expect(auth.resetAccount?.id.value, 'reader-1');
    expect(auth.resetTemporaryPassword, 'Temporary-2026');
  });

  test("the server's refusal reaches the caller unchanged", () async {
    auth.nextResetFailure = const PermissionFailure(
      'That account is not in your service area.',
    );

    final result = await ResetAccountPassword(auth: auth)(
      account: reader,
      temporaryPassword: 'Temporary-2026',
      confirmPassword: 'Temporary-2026',
    );

    expect(messageOf(result), 'That account is not in your service area.');
  });
}
