import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/repositories/account_management_repository.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../providers.dart';

final accountManagementRepositoryProvider =
    Provider<AccountManagementRepository>(
      (ref) => AccountManagementRepository(ref.watch(supabaseClientProvider)),
    );
final accountWorkspaceProvider = FutureProvider.autoDispose<AccountRow>(
  (ref) => ref.watch(accountManagementRepositoryProvider).workspace(),
);
final myPresidentTransfersProvider =
    FutureProvider.autoDispose<List<AccountRow>>(
      (ref) => ref.watch(accountManagementRepositoryProvider).transfers(),
    );
final accountPendingWorkProvider = StreamProvider.autoDispose<int>(
  (ref) => ref
      .watch(outboxRepositoryProvider)
      .watchAll()
      .map(
        (rows) => rows.where((row) => row.status != OutboxStatus.synced).length,
      ),
);
