import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart' as domain;
import '../providers.dart';
import 'auth_controller.dart';

/// The household linked to the current login, including its offline copy.
/// Changing identity or access version discards the previous link check.
final linkedHouseholdProvider = FutureProvider<domain.Consumer?>(
  (ref) async {
    final scope = ref.watch(
      authControllerProvider.select((auth) => auth.value?.accessScope),
    );
    if (scope == null) return null;
    final result = await ref
        .watch(consumerRepositoryProvider)
        .signedInConsumer();
    return switch (result) {
      Ok(:final value) => value,
      Err(:final failure) => throw failure,
    };
  },
  // Navigation must finish on a failed check. Profile refresh, a new access
  // version or successful linking starts another check explicitly.
  retry: (_, _) => null,
);
