import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/managed_account.dart';
import '../../domain/usecases/admin/reset_account_password.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

const PermissionFailure _notAnAreaPresident = PermissionFailure(
  'Only an Area President can reset a password in their service area.',
);

/// The accounts this Area President may reset, in their own area.
///
/// autoDispose, so a staff member created a moment ago on the Accounts tab
/// is in the list the next time this screen opens.
final managedAccountsProvider =
    FutureProvider.autoDispose<List<ManagedAccount>>((Ref ref) async {
      final AppUser? user = await ref.watch(authControllerProvider.future);
      final areaId = user?.areaId;
      if (user is! AdminUser || areaId == null) throw _notAnAreaPresident;

      final result = await ref
          .watch(authRepositoryProvider)
          .managedAccounts(areaId);
      return switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };
    });

final class AdminResetPasswordState {
  final bool isSubmitting;
  final AppFailure? failure;

  /// Set once a reset has succeeded, so the screen can say who it was for.
  final ManagedAccount? resetFor;

  /// The new temporary password, set with [resetFor], to be shown once.
  final String? temporaryPassword;

  const AdminResetPasswordState({
    this.isSubmitting = false,
    this.failure,
    this.resetFor,
    this.temporaryPassword,
  });
}

/// Resets a forgotten password, without knowing about Supabase.
class AdminResetPasswordController extends Notifier<AdminResetPasswordState> {
  @override
  AdminResetPasswordState build() => const AdminResetPasswordState();

  Future<void> reset({required ManagedAccount account}) async {
    if (state.isSubmitting) return;

    final AppUser? user = await ref.read(authControllerProvider.future);
    if (user is! AdminUser || user.areaId == null) {
      state = const AdminResetPasswordState(failure: _notAnAreaPresident);
      return;
    }

    state = const AdminResetPasswordState(isSubmitting: true);

    final result = await ref.read(resetAccountPasswordUseCaseProvider)(
      account: account,
    );

    state = switch (result) {
      Ok(:final value) => AdminResetPasswordState(
        resetFor: account,
        temporaryPassword: value,
      ),
      Err(:final failure) => AdminResetPasswordState(failure: failure),
    };
  }

  /// Back to choosing an account, with nothing left over from the last one.
  void clear() => state = const AdminResetPasswordState();
}

/// Kept beside the controller, like the staff-creation use case, so the
/// shared provider composition stays unchanged.
final resetAccountPasswordUseCaseProvider = Provider<ResetAccountPassword>(
  (Ref ref) => ResetAccountPassword(
    auth: ref.watch(authRepositoryProvider),
    newTemporaryPassword: ref.watch(temporaryPasswordFactoryProvider),
  ),
);

/// autoDispose, so leaving the screen after a reset does not reopen it on
/// the success message — or its password — next time.
final adminResetPasswordControllerProvider =
    NotifierProvider.autoDispose<
      AdminResetPasswordController,
      AdminResetPasswordState
    >(AdminResetPasswordController.new);
