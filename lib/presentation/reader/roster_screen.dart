import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/area_roster.dart';
import '../auth/auth_controller.dart';
import '../common/consumer_search.dart';
import '../common/failure_banner.dart';
import '../common/local_search_field.dart';
import '../common/local_sort_button.dart';
import '../router.dart';
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
        title: Text(user == null ? 'My round' : 'My round · ${user.firstName}'),
        actions: <Widget>[
          // Step 2 of the month: the list that goes onto BOHECO's paper.
          IconButton(
            tooltip: 'Reading sheet',
            icon: const Icon(Icons.table_rows_outlined),
            onPressed: () => context.push(Routes.readingSheet),
          ),
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
              // Retrying tries the server again, not just the empty cache.
              onRetry: () {
                ref.invalidate(initialRosterRefreshProvider);
                ref.invalidate(rosterControllerProvider);
              },
            ),
          ),
          data: (RosterView view) => _RosterBody(view: view),
        ),
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final waiting =
        ref.read(rosterControllerProvider).value?.roster.waitingToSync ?? 0;

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

class _RosterBody extends ConsumerStatefulWidget {
  final RosterView view;

  const _RosterBody({required this.view});

  @override
  ConsumerState<_RosterBody> createState() => _RosterBodyState();
}

class _RosterBodyState extends ConsumerState<_RosterBody> {
  final TextEditingController _search = TextEditingController();
  _RosterSort _sort = _RosterSort.routeOrder;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roster = widget.view.roster;
    // The working list contains only houses that still need a reading.
    // Queued readings are durable and visible in the sync status/Profile;
    // leaving the household here would invite a duplicate visit. Synced
    // readings stay represented by the progress totals rather than returning
    // as a second, non-actionable list.
    final List<RosterEntry> matching = roster.remaining
        .where(
          (RosterEntry entry) =>
              consumerMatchesSearch(entry.consumer, _search.text),
        )
        .toList();
    if (_sort != _RosterSort.routeOrder) {
      matching.sort((a, b) {
        final compared = a.consumer.fullName.toLowerCase().compareTo(
          b.consumer.fullName.toLowerCase(),
        );
        return _sort == _RosterSort.nameAz ? compared : -compared;
      });
    }

    return RefreshIndicator(
      onRefresh: () async {
        final failure = await ref
            .read(rosterControllerProvider.notifier)
            .refreshFromServer();
        if (failure != null && context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(failure.message)));
        }
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          _ProgressCard(
            roster: roster,
            lastRefreshedAt: widget.view.lastRefreshedAt,
          ),
          if (roster.waitingToSync > 0) ...<Widget>[
            const SizedBox(height: 12),
            _WaitingToSyncCard(count: roster.waitingToSync),
          ],
          const SizedBox(height: 16),
          if (roster.remaining.isNotEmpty) ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: LocalSearchField(
                    fieldKey: const ValueKey<String>('reader-roster-search'),
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    hintText: 'Search name, account, purok or meter',
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 132,
                  child: LocalSortButton<_RosterSort>(
                    buttonKey: const ValueKey('reader-roster-sort'),
                    value: _sort,
                    options: const <LocalSortOption<_RosterSort>>[
                      LocalSortOption(
                        value: _RosterSort.routeOrder,
                        label: 'Route order',
                        icon: Icons.route_outlined,
                      ),
                      LocalSortOption(
                        value: _RosterSort.nameAz,
                        label: 'Name A–Z',
                        icon: Icons.sort_by_alpha,
                      ),
                      LocalSortOption(
                        value: _RosterSort.nameZa,
                        label: 'Name Z–A',
                        icon: Icons.sort_by_alpha,
                      ),
                    ],
                    onChanged: (value) => setState(() => _sort = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (roster.entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No households saved on this phone yet. Pull down to load '
                'your area while you have a connection.',
                textAlign: TextAlign.center,
              ),
            ),

          if (roster.entries.isNotEmpty && roster.remaining.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: <Widget>[
                  Icon(Icons.task_alt, size: 40),
                  SizedBox(height: 12),
                  Text(
                    'Every household has been recorded for this cycle.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          if (roster.remaining.isNotEmpty && matching.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: <Widget>[
                  Icon(
                    Icons.search_off,
                    size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No household matches that search.',
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

          // Still to read, first. A reader works down this list on foot, and
          // as the round progresses the finished houses would otherwise pile
          // up above the next one they actually have to walk to.
          if (matching.isNotEmpty) ...<Widget>[
            Text(
              'Still to read (${matching.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final RosterEntry entry in matching)
              _HouseholdTile(
                entry: entry,
                onOpen: () => _openEntry(context, ref, entry),
              ),
          ],
        ],
      ),
    );
  }

  /// Opens the reading form and refreshes the round on the way back.
  ///
  /// `push`, not `go`. With `go` the form replaced the round instead of
  /// sitting on top of it, so it had no back arrow and Android's back button
  /// had nothing to pop — a reader who tapped the wrong house could only get
  /// out by recording a reading they did not mean to take.
  ///
  /// The round then has to be refreshed by hand: with the form pushed on top,
  /// the list underneath is still alive and would show the household as
  /// unread after it had just been recorded.
  static Future<void> _openEntry(
    BuildContext context,
    WidgetRef ref,
    RosterEntry entry,
  ) async {
    await context.push('/reader/entry/${entry.consumer.id.value}');
    ref.invalidate(rosterControllerProvider);
  }
}

enum _RosterSort { routeOrder, nameAz, nameZa }

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
            // how old it is. It says what was refreshed - the household list
            // on this phone - because "Updated just now" on its own read as
            // though something had been read or billed today.
            Row(
              children: <Widget>[
                Icon(
                  Icons.sync,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    lastRefreshedAt == null
                        ? 'Household list not yet downloaded from the server'
                        : 'Household list synced ${_ago(lastRefreshedAt!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
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
            Icon(
              Icons.cloud_upload_outlined,
              color: scheme.onSecondaryContainer,
            ),
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HouseholdTile extends StatelessWidget {
  final RosterEntry entry;

  /// Null for a household already done this cycle. FR-23 refuses a second
  /// reading anyway; not offering the tap is kinder than refusing it after.
  final VoidCallback? onOpen;

  const _HouseholdTile({required this.entry, required this.onOpen});

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
        onTap: onOpen,
      ),
    );
  }
}
