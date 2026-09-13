import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/security/local_auth_device_unlock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';

/// A [LocalAuthentication] whose prompt answers however the test says.
class _ScriptedPrompt extends LocalAuthentication {
  final bool supported;
  final bool throwsOnSupportCheck;
  final bool confirms;
  final LocalAuthExceptionCode? fails;

  int prompts = 0;
  bool? askedBiometricOnly;

  _ScriptedPrompt({
    this.supported = true,
    this.throwsOnSupportCheck = false,
    this.confirms = true,
    this.fails,
  });

  @override
  Future<bool> isDeviceSupported() async {
    if (throwsOnSupportCheck) throw StateError('plugin not registered');
    return supported;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    // Widened from Iterable<AuthMessages>, which local_auth does not export.
    Iterable<Object> authMessages = const <Object>[],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    prompts++;
    askedBiometricOnly = biometricOnly;
    final LocalAuthExceptionCode? code = fails;
    if (code != null) {
      throw LocalAuthException(
        code: code,
        description: 'BiometricPrompt reported ${code.name}',
      );
    }
    return confirms;
  }
}

/// The only code that talks to the fingerprint sensor, and so the only place
/// that decides what a person reads when the sensor says no.
///
/// The Phase 2 rubric asks that every foreseeable error display a
/// user-friendly message without exposing technical details. These tests hold
/// this class to that for every answer the phone can give.
void main() {
  String messageOf(Result<void> result) => switch (result) {
    Err(:final failure) => failure.message,
    Ok() => fail('expected the prompt to be refused'),
  };

  test("the phone's PIN counts, not only the fingerprint sensor", () async {
    // Phase 1: "the device biometric or the device passcode".
    final prompt = _ScriptedPrompt();

    await LocalAuthDeviceUnlock(prompt).confirmIdentity(reason: 'test');

    expect(prompt.askedBiometricOnly, isFalse);
  });

  test('a confirmed prompt lets the person through', () async {
    final result = await LocalAuthDeviceUnlock(
      _ScriptedPrompt(),
    ).confirmIdentity(reason: 'test');

    expect(result, isA<Ok<void>>());
  });

  test(
    'a prompt that answers no without an error does not let anyone in',
    () async {
      // authenticate() can return false instead of throwing. Treating false as
      // anything but a refusal would open the lock for whoever tapped the button.
      final result = await LocalAuthDeviceUnlock(
        _ScriptedPrompt(confirms: false),
      ).confirmIdentity(reason: 'test');

      expect(messageOf(result), LocalAuthDeviceUnlock.cancelled);
    },
  );

  group('every refusal reaches the screen as a plain sentence', () {
    Future<Result<void>> refusedWith(LocalAuthExceptionCode code) =>
        LocalAuthDeviceUnlock(
          _ScriptedPrompt(fails: code),
        ).confirmIdentity(reason: 'test');

    test(
      'cancelling, or the prompt timing out, says it was cancelled',
      () async {
        for (final LocalAuthExceptionCode code in <LocalAuthExceptionCode>[
          LocalAuthExceptionCode.userCanceled,
          LocalAuthExceptionCode.systemCanceled,
          LocalAuthExceptionCode.timeout,
        ]) {
          expect(
            messageOf(await refusedWith(code)),
            LocalAuthDeviceUnlock.cancelled,
            reason: code.name,
          );
        }
      },
    );

    test('no screen lock says what to set up', () async {
      expect(
        messageOf(await refusedWith(LocalAuthExceptionCode.noCredentialsSet)),
        contains('no screen lock'),
      );
    });

    test('a locked-out sensor says how to get past it', () async {
      expect(
        messageOf(await refusedWith(LocalAuthExceptionCode.temporaryLockout)),
        LocalAuthDeviceUnlock.tooManyTries,
      );
      expect(
        messageOf(await refusedWith(LocalAuthExceptionCode.biometricLockout)),
        contains('PIN'),
      );
    });

    test('a code nobody planned for still gets a sentence', () async {
      // The plugin reserves the right to add codes in any release.
      expect(
        messageOf(await refusedWith(LocalAuthExceptionCode.deviceError)),
        LocalAuthDeviceUnlock.couldNotCheck,
      );
    });

    test('the technical detail is kept, but never shown', () async {
      final result = await refusedWith(LocalAuthExceptionCode.userCanceled);
      final AppFailure failure = (result as Err<void>).failure;

      expect(failure, isA<AuthFailure>());
      expect(failure.message, isNot(contains('LocalAuthException')));
      expect(failure.message, isNot(contains('BiometricPrompt')));
      expect(failure.debugDetail, contains('LocalAuthException'));
    });
  });

  group('whether the phone can confirm anyone at all', () {
    test('a phone without a screen lock cannot', () async {
      expect(
        await LocalAuthDeviceUnlock(
          _ScriptedPrompt(supported: false),
        ).isAvailable(),
        isFalse,
      );
    });

    test(
      'a plugin that errors counts as unavailable, not as a crash',
      () async {
        expect(
          await LocalAuthDeviceUnlock(
            _ScriptedPrompt(throwsOnSupportCheck: true),
          ).isAvailable(),
          isFalse,
        );
      },
    );
  });
}
