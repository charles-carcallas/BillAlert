import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/usecases/auth/change_password.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test(
    'offline, it says nothing changed, not that the work will sync',
    () async {
      // The app's general offline message promises the work is saved and will
      // sync. That is true of a reading, and false of a password.
      final FakeAuthRepository auth = FakeAuthRepository()
        ..nextChangePasswordFailure = const NetworkFailure();

      final Result<void> result = await ChangePassword(auth: auth)(
        newPassword: 'ElenaNew2026',
        confirmPassword: 'ElenaNew2026',
      );

      final AppFailure failure = (result as Err<void>).failure;
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, contains('Nothing was changed'));
      expect(failure.message, isNot(contains('sync')));
    },
  );

  test(
    'any other refusal reaches the screen as the server described it',
    () async {
      final FakeAuthRepository auth = FakeAuthRepository()
        ..nextChangePasswordFailure = const ValidationFailure(
          'That password is too easy to guess. Please choose a longer one.',
        );

      final Result<void> result = await ChangePassword(auth: auth)(
        newPassword: 'ElenaNew2026',
        confirmPassword: 'ElenaNew2026',
      );

      expect((result as Err<void>).failure.message, contains('too easy'));
    },
  );
}
