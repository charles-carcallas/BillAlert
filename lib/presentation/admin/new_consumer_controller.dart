// `Consumer` here means a household, not Riverpod's widget.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/usecases/admin/create_consumer.dart';
import '../../domain/usecases/admin/register_household.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import 'household_login_controller.dart';

final class AdminNewConsumerState {
  final bool isSubmitting;
  final AppFailure? failure;

  /// The household, and its sign-in or why it could not be created.
  final RegisteredHousehold? registered;

  const AdminNewConsumerState({
    this.isSubmitting = false,
    this.failure,
    this.registered,
  });
}

/// ADM-03 + MTR-04 — registers a household and gives it its sign-in.
///
/// The controller gets the area and creator from the signed-in Admin. The
/// screen cannot choose either value, and no Supabase type crosses this layer.
class AdminNewConsumerController extends Notifier<AdminNewConsumerState> {
  @override
  AdminNewConsumerState build() => const AdminNewConsumerState();

  Future<void> create({
    required String consumerNo,
    required String firstName,
    required String lastName,
    required String contactNumber,
    required String purok,
    required String meterSerialNo,
    required String username,
  }) async {
    if (state.isSubmitting) return;

    final AppUser? user = await ref.read(authControllerProvider.future);
    if (user is! AdminUser || user.areaId == null) {
      state = const AdminNewConsumerState(
        failure: PermissionFailure(
          'Only an Area President can create a consumer in their service area.',
        ),
      );
      return;
    }

    state = const AdminNewConsumerState(isSubmitting: true);

    final result = await ref.read(registerHouseholdUseCaseProvider)(
      consumerNo: consumerNo,
      firstName: firstName,
      lastName: lastName,
      contactNumber: contactNumber,
      purok: purok,
      meterSerialNo: meterSerialNo,
      username: username,
      areaId: user.areaId!,
      createdBy: user.id,
    );

    state = switch (result) {
      Ok(:final value) => AdminNewConsumerState(registered: value),
      Err(:final failure) => AdminNewConsumerState(failure: failure),
    };
  }

  void createAnother() {
    state = const AdminNewConsumerState();
  }
}

/// Kept beside the controller because the shared providers file is owned by
/// the app-composition work. It still depends on the domain interface exposed
/// there, not on ConsumerRepositoryImpl.
final createConsumerUseCaseProvider = Provider<CreateConsumer>(
  (Ref ref) => CreateConsumer(consumers: ref.watch(consumerRepositoryProvider)),
);

final registerHouseholdUseCaseProvider = Provider<RegisterHousehold>(
  (Ref ref) => RegisterHousehold(
    createConsumer: ref.watch(createConsumerUseCaseProvider),
    createLogin: ref.watch(createHouseholdLoginUseCaseProvider),
  ),
);

final adminNewConsumerControllerProvider =
    NotifierProvider<AdminNewConsumerController, AdminNewConsumerState>(
      AdminNewConsumerController.new,
    );
