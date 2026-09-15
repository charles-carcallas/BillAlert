import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/household_login.dart';
import '../../domain/usecases/admin/create_household_login.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

const PermissionFailure _notAnAreaPresident = PermissionFailure(
  'Only an Area President can give a household in their service area a '
  'sign-in.',
);

/// MTR-04: the households in this Area President's area that cannot sign in
/// yet.
///
/// autoDispose, so a household created a moment ago on the Accounts tab is
/// in the list the next time this screen opens, and one just given a sign-in
/// is not.
final householdsWithoutLoginProvider =
    FutureProvider.autoDispose<List<HouseholdWithoutLogin>>((Ref ref) async {
      final AppUser? user = await ref.watch(authControllerProvider.future);
      final areaId = user?.areaId;
      if (user is! AdminUser || areaId == null) throw _notAnAreaPresident;

      final result = await ref
          .watch(authRepositoryProvider)
          .householdsWithoutLogin(areaId);
      return switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };
    });

final class AdminHouseholdLoginState {
  final bool isSubmitting;
  final AppFailure? failure;

  /// Set once the sign-in exists, so the screen can show the username and
  /// temporary password to hand over.
  final CreatedHouseholdLogin? created;

  const AdminHouseholdLoginState({
    this.isSubmitting = false,
    this.failure,
    this.created,
  });
}

/// Gives a household a sign-in, without knowing about Supabase.
class AdminHouseholdLoginController extends Notifier<AdminHouseholdLoginState> {
  @override
  AdminHouseholdLoginState build() => const AdminHouseholdLoginState();

  Future<void> create({
    required HouseholdWithoutLogin household,
    required String username,
  }) async {
    if (state.isSubmitting) return;

    final AppUser? user = await ref.read(authControllerProvider.future);
    if (user is! AdminUser || user.areaId == null) {
      state = const AdminHouseholdLoginState(failure: _notAnAreaPresident);
      return;
    }

    state = const AdminHouseholdLoginState(isSubmitting: true);

    final result = await ref.read(createHouseholdLoginUseCaseProvider)(
      household: household,
      username: username,
    );

    state = switch (result) {
      Ok(:final value) => AdminHouseholdLoginState(created: value),
      Err(:final failure) => AdminHouseholdLoginState(failure: failure),
    };
  }

  /// Back to choosing a household, with nothing left over from the last one.
  void clear() => state = const AdminHouseholdLoginState();
}

/// Kept beside the controller, like the staff-creation use case, so the
/// shared provider composition stays unchanged.
final createHouseholdLoginUseCaseProvider = Provider<CreateHouseholdLogin>(
  (Ref ref) => CreateHouseholdLogin(
    auth: ref.watch(authRepositoryProvider),
    newTemporaryPassword: ref.watch(temporaryPasswordFactoryProvider),
  ),
);

/// autoDispose, so leaving the screen after creating a sign-in does not
/// reopen it on the success message — or its password — next time.
final adminHouseholdLoginControllerProvider =
    NotifierProvider.autoDispose<
      AdminHouseholdLoginController,
      AdminHouseholdLoginState
    >(AdminHouseholdLoginController.new);
