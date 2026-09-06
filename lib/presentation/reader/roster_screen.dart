import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/area_roster.dart';
import '../auth/auth_controller.dart';
import '../common/failure_banner.dart';
import 'roster_controller.dart';

/// MTR-11 — the meter reader's round for this billing cycle.
///
/// Everything here is drawn from the encrypted cache, so it works standing in
/// a barangay with no signal. The counters count a household as done when the
/// reading is queued, not when it has uploaded.
class RosterScreen extends ConsumerWidget {
  const RosterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(rosterControllerProvider);
    final user = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          user == null ? 'My round' : 'My round · ${user.firstName}',
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: state.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => Padding(
            padding: const EdgeInsets.all(16),
            child: FailureBanner(
              failure: error is AppFailure
                  ? error
                  : ServerFailure(ServerFailure.defaultMessage, '$error'),
              onRetry: () => ref.invalidate(rosterControllerProvider),
            ),
          ),
          data: (RosterView view) => _RosterBody(view: view),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final waiting = ref.read(rosterControllerProvider).value?.roster
            .waitingToSync ??
        0;

    // Signing out empties the cache. If there are readings still queued, the
    // reader has to be told before that happens, not afterwards.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          waiting == 0
              ? 'Everything you recorded has been sent.'
              : 'You still have $waiting reading${waiting == 1 ? '' : 's'} '
                  'waiting to sync. They stay saved on this phone and will be '
                  'sent when you sign in again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _RosterBody extends ConsumerWidget {
  final RosterView view;

  const _RosterBody({required this.view});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = view.roster;

    return RefreshIndicator(
      onRefresh: () async {
        final failure = await ref
            .read(rosterControllerProvider.notifier)
            .refreshFromServer();
        if (failure != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(failure.message)),
          );
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _ProgressCard(roster: roster, lastRefreshedAt: view.lastRefreshedAt),
          if (roster.waitingToSync > 0) ...<Widget>[
            const SizedBox(height: 12),
            _WaitingToSyncCard(count: roster.waitingToSync),
          ],
          const SizedBox(height: 16),
          Text(
            'Households (${roster.totalConsumers})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (roster.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No households saved on this phone yet. Pull down to load '
                'your area while you have a connection.',
                textAlign: TextAlign.center,
              ),
            ),
          for (final RosterEntry entry in roster.entries)
            _HouseholdTile(entry: entry),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final AreaRoster roster;
  final DateTime? lastRefreshedAt;

  const _ProgressCard({required this.roster, this.lastRefreshedAt});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              roster.cycle.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${roster.readCount} of ${roster.totalConsumers} recorded'
              '  ·  ${roster.remainingCount} to go',
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: roster.totalConsumers == 0
                  ? 0
                  : roster.readCount / roster.totalConsumers,
              minHeight: 8,
            ),
            const SizedBox(height: 12),
            // GEN-11: never let anybody read a cached number without knowing
            // how old it is.
            Text(
              lastRefreshedAt == null
                  ? 'Not yet loaded from the server'
                  : 'Updated ${_ago(lastRefreshedAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  static String _ago(DateTime instant) {
    final difference = DateTime.now().toUtc().difference(instant);
    if (difference.inMinutes < 1) return 'just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes} min ago';
    if (difference.inHours < 24) return '${difference.inHours} h ago';
    return '${difference.inDays} d ago';
  }
}

class _WaitingToSyncCard extends ConsumerWidget {
  final int count;

  const _WaitingToSyncCard({required this.count});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.cloud_upload_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count reading${count == 1 ? '' : 's'} waiting to sync',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton(
              onPressed: () => _sync(context, ref),
              child: const Text('Sync now'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sync(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(rosterControllerProvider.notifier).syncNow();
    if (!context.mounted) return;

    final message = switch (result) {
      Ok(:final value) when value.succeeded > 0 =>
        '${value.succeeded} sent${value.failed > 0 ? ', ${value.failed} could not be sent' : ''}',
      Ok(:final value) when value.failed > 0 =>
        '${value.failed} could not be sent. Open the item to see why.',
      Ok() => 'Nothing waiting to sync.',
      Err(:final failure) => failure.message,
    };

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HouseholdTile extends StatelessWidget {
  final RosterEntry entry;

  const _HouseholdTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final consumer = entry.consumer;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(consumer.fullName),
        subtitle: Text(
          '${consumer.consumerNo}'
          '${consumer.purok == null ? '' : '  ·  ${consumer.purok}'}\n'
          'Last reading ${consumer.previousReading.format()}',
        ),
        isThreeLine: true,
        trailing: entry.isDone
            ? Chip(
                avatar: Icon(
                  entry.isQueuedForSync ? Icons.schedule : Icons.check,
                  size: 18,
                ),
                label: Text(entry.isQueuedForSync ? 'Queued' : 'Recorded'),
                backgroundColor: scheme.secondaryContainer,
              )
            : const Icon(Icons.chevron_right),
        // A household already done this cycle cannot be opened again. FR-23
        // is refused by the use case anyway; not offering it is kinder.
        onTap: entry.isDone
            ? null
            : () => context.go('/reader/entry/${consumer.id.value}'),
      ),
    );
  }
}
