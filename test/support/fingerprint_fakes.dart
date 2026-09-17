import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/security/device_unlock.dart';
import 'package:billalert/domain/security/fingerprint_setting.dart';
import 'package:billalert/domain/security/password_verifier.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/app_lock_controller.dart';

/// The phone's screen lock, without a phone.
final class FakeDeviceUnlock implements DeviceUnlock {
  bool available;

  /// Returned by every prompt while set. Null means the person confirmed.
  AppFailure? failure;

  int prompts = 0;

  FakeDeviceUnlock({this.available = true, this.failure});

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<Result<void>> confirmIdentity({required String reason}) async {
    prompts++;
    final AppFailure? answer = failure;
    return answer == null ? const Ok<void>(null) : Err<void>(answer);
  }
}

/// Fingerprint sign-in's setting, held in memory.
final class FakeFingerprintSetting implements FingerprintSetting {
  String? onFor;
  final Set<String> offeredTo = <String>{};

  FakeFingerprintSetting({this.onFor});

  @override
  Future<bool> isOnFor(ProfileId profile) async => onFor == profile.value;

  @override
  Future<void> turnOnFor(ProfileId profile) async {
    onFor = profile.value;
  }

  @override
  Future<void> turnOff() async {
    onFor = null;
  }

  @override
  Future<bool> wasOfferedTo(ProfileId profile) async =>
      offeredTo.contains(profile.value);

  @override
  Future<void> markOfferedTo(ProfileId profile) async {
    offeredTo.add(profile.value);
  }
}

/// An [AppLockController] that starts locked, for screens drawn mid-lock.
/// Remembers passwords in memory, as if the server had accepted them.
final class FakePasswordVerifier implements PasswordVerifier {
  final Map<String, String> accepted = <String, String>{};

  @override
  Future<void> remember(ProfileId profile, String password) async =>
      accepted[profile.value] = password;

  @override
  Future<bool?> matches(ProfileId profile, String password) async {
    final String? saved = accepted[profile.value];
    return saved == null ? null : saved == password;
  }

  @override
  Future<void> forget(ProfileId profile) async =>
      accepted.remove(profile.value);
}

class LockedAppLockController extends AppLockController {
  @override
  AppLockState build() => const AppLockState(locked: true);
}
