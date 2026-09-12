import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/staff_account.dart';
import '../../domain/usecases/admin/create_staff_account.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

final class AdminNewStaffState {
  final bool isSubmitting;
  final AppFailure? failure;
  final CreatedStaffAccount? created;

  const AdminNewStaffState({
    this.isSubmitting = false,
    this.failure,
    this.created,
  });
}

/// FR-31 — coordinates staff provisioning without knowing about Supabase.
class AdminNewStaffController extends Notifier<AdminNewStaffState> {
  @override
  AdminNewStaffState build() => const AdminNewStaffState();

  Future<void> create({
    required String username,
    required String firstName,
    required String lastName,
    required String contactNumber,
    required StaffRole role,
    required String temporaryPassword,
    required String confirmPassword,
  }) async {
    if (state.isSubmitting) return;

    final user = await ref.read(authControllerProvider.future);
    if (user is! AdminUser || user.areaId == null) {
      state = const AdminNewStaffState(
        failure: PermissionFailure(
          'Only an Area President can create a staff account in their '
          'service area.',
        ),
      );
      return;
    }

    state = const AdminNewStaffState(isSubmitting: true);

    final result = await ref.read(createStaffAccountUseCaseProvider)(
      username: username,
      firstName: firstName,
      lastName: lastName,
      contactNumber: contactNumber,
      role: role,
      temporaryPassword: temporaryPassword,
      confirmPassword: confirmPassword,
    );

    state = switch (result) {
      Ok(:final value) => AdminNewStaffState(created: value),
      Err(:final failure) => AdminNewStaffState(failure: failure),
    };
  }

  void createAnother() => state = const AdminNewStaffState();
}

/// Kept beside the controller so the shared provider composition remains
/// unchanged. The use case still depends only on the domain repository.
final createStaffAccountUseCaseProvider = Provider<CreateStaffAccount>(
  (Ref ref) => CreateStaffAccount(auth: ref.watch(authRepositoryProvider)),
);

final adminNewStaffControllerProvider =
    NotifierProvider<AdminNewStaffController, AdminNewStaffState>(
      AdminNewStaffController.new,
    );
