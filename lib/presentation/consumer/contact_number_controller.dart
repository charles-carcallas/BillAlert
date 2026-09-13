import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/usecases/consumer/update_own_contact_number.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

final class ConsumerContactNumberState {
  final bool isSubmitting;
  final AppFailure? failure;
  final String? savedNumber;

  const ConsumerContactNumberState({
    this.isSubmitting = false,
    this.failure,
    this.savedNumber,
  });
}

class ConsumerContactNumberController
    extends Notifier<ConsumerContactNumberState> {
  @override
  ConsumerContactNumberState build() => const ConsumerContactNumberState();

  Future<void> update(String contactNumber) async {
    if (state.isSubmitting) return;

    final AppUser? user = await ref.read(authControllerProvider.future);
    if (user is! ConsumerUser) {
      state = const ConsumerContactNumberState(
        failure: PermissionFailure(
          'Only a consumer can change the SMS number for their household.',
        ),
      );
      return;
    }

    state = const ConsumerContactNumberState(isSubmitting: true);
    final result = await ref.read(updateOwnContactNumberProvider)(
      contactNumber: contactNumber,
    );
    state = switch (result) {
      Ok(:final value) => ConsumerContactNumberState(savedNumber: value),
      Err(:final failure) => ConsumerContactNumberState(failure: failure),
    };
  }

  void reset() => state = const ConsumerContactNumberState();
}

final updateOwnContactNumberProvider = Provider<UpdateOwnContactNumber>(
  (Ref ref) =>
      UpdateOwnContactNumber(consumers: ref.watch(consumerRepositoryProvider)),
);

final consumerContactNumberControllerProvider =
    NotifierProvider<
      ConsumerContactNumberController,
      ConsumerContactNumberState
    >(ConsumerContactNumberController.new);
