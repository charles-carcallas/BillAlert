// `Consumer` here means a household, not Riverpod's widget.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/usecases/admin/create_consumer.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

final class AdminNewConsumerState {
  final bool isSubmitting;
  final AppFailure? failure;
  final Consumer? created;

  const AdminNewConsumerState({
    this.isSubmitting = false,
    this.failure,
    this.created,
  });
}

/// ADM-03 — creates a household, never an authentication account.
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

    final result = await ref.read(createConsumerUseCaseProvider)(
      consumerNo: consumerNo,
      firstName: firstName,
      lastName: lastName,
      contactNumber: contactNumber,
      purok: purok,
      areaId: user.areaId!,
      createdBy: user.id,
    );

    state = switch (result) {
      Ok(:final value) => AdminNewConsumerState(created: value),
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

final adminNewConsumerControllerProvider =
    NotifierProvider<AdminNewConsumerController, AdminNewConsumerState>(
      AdminNewConsumerController.new,
    );
