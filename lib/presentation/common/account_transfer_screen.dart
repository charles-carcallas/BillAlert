import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../admin/account_management_forms.dart';
import '../admin/account_management_providers.dart';
import '../auth/auth_controller.dart';
import 'transfer_guide.dart';

/// This route is available to every signed-in identity, including candidates.
class AccountTransferScreen extends ConsumerStatefulWidget {
  const AccountTransferScreen({super.key});
  @override
  ConsumerState<AccountTransferScreen> createState() =>
      _AccountTransferScreenState();
}

class _AccountTransferScreenState extends ConsumerState<AccountTransferScreen> {
  bool busy = false;
  String? message;
  Future<void> act(String id, String action) async {
    if (busy) return;
    final form = await accountForm(
      context,
      title: switch (action) {
        'accept' => 'Accept nomination',
        'complete' => 'Complete handover',
        _ => 'Cancel transfer',
      },
      fields: const {},
      reconciliation: action == 'complete',
      explanation: action == 'complete'
          ? 'This activates the accepted successor and ends your work access. Your household access and historical records remain.'
          : action == 'accept'
          ? 'Accept the nomination after changing your temporary password. Work access begins only when the outgoing president completes it.'
          : 'Cancel this pending transfer. No successor will be activated.',
    );
    if (form == null || !mounted || busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await ref
          .read(accountManagementRepositoryProvider)
          .transfer(id, action, reconciled: form['reconciled'] == 'true');
      if (mounted) {
        setState(
          () => message = action == 'complete'
              ? 'Transfer completed. Refreshing your access. If work tabs remain, reconnect and refresh before continuing.'
              : 'Transfer updated.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) {
        ref.invalidate(myPresidentTransfersProvider);
        ref.invalidate(accountWorkspaceProvider);
        // A lost completion response may still have changed our capabilities.
        await ref.read(authControllerProvider.notifier).confirmSession();
        if (mounted) setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Area President transfer'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy
                ? null
                : () => ref.invalidate(myPresidentTransfersProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('Sign in to view transfers.'))
          : ref
                .watch(myPresidentTransfersProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(
                    child: Text(
                      'Could not load transfers. Connect and refresh.',
                    ),
                  ),
                  data: (rows) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                        children: [
                          const TransferGuide(),
                          const SizedBox(height: 28),
                          Text(
                            'Your transfers',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          if (busy) const LinearProgressIndicator(),
                          if (message != null) Text(message!),
                          if (rows.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'No transfers yet. Nominations addressed to you will appear here.',
                              ),
                            ),
                          for (final t in rows)
                            Card(
                              margin: const EdgeInsets.only(bottom: 16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${t['area_name'] ?? 'Service area'}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 12),
                                    Chip(
                                      label: Text(switch (t['status']) {
                                        'pending' => 'Awaiting acceptance',
                                        'accepted' => 'Ready for handover',
                                        'completed' => 'Completed',
                                        'cancelled' => 'Cancelled',
                                        _ => '${t['status']}',
                                      }),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '${t['outgoing_name'] ?? 'Outgoing president'} → ${t['successor_name'] ?? 'Successor'}',
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${t['reason']}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 20),
                                    if (t['successor_id'] == user.id.value &&
                                        t['status'] == 'pending')
                                      FilledButton(
                                        onPressed:
                                            busy || user.mustChangePassword
                                            ? null
                                            : () => act(
                                                t['id'] as String,
                                                'accept',
                                              ),
                                        child: const Text('Accept nomination'),
                                      ),
                                    if (t['outgoing_id'] == user.id.value &&
                                        t['status'] == 'accepted')
                                      FilledButton(
                                        onPressed: busy
                                            ? null
                                            : () => act(
                                                t['id'] as String,
                                                'complete',
                                              ),
                                        child: const Text('Complete transfer'),
                                      ),
                                    if (t['outgoing_id'] == user.id.value &&
                                        {
                                          'pending',
                                          'accepted',
                                        }.contains(t['status']))
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => act(
                                                t['id'] as String,
                                                'cancel',
                                              ),
                                        child: const Text('Cancel transfer'),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
