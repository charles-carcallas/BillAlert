import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';
import '../common/settlement_panel.dart';

class ReserveFundReportScreen extends ConsumerWidget {
  const ReserveFundReportScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Reserve fund report')),
      body: SafeArea(
        child: user is AdminUser && user.hasWorkAccess
            ? RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(settlementSnapshotProvider);
                  await ref.read(settlementSnapshotProvider.future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: const [SettlementPanel()],
                ),
              )
            : const Center(child: Text('Admin work access required.')),
      ),
    );
  }
}
