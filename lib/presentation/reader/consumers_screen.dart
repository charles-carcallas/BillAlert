import 'package:flutter/material.dart';
// `Consumer` here means a household. Riverpod's widget of that name is not
// used in this file, so the package's is hidden rather than the domain's word
// being bent to suit it.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/value_objects/ph_date.dart';
import '../auth/auth_controller.dart';
import '../common/consumer_search.dart';
import '../common/failure_banner.dart';
import '../common/local_search_field.dart';
import '../common/local_sort_button.dart';
import '../providers.dart';
import 'household_details_sheet.dart';
import 'roster_controller.dart';

/// The households of this reader's area, from the encrypted cache.
///
/// Reads the cache, not the network. The meter reader opens this standing in
/// a barangay with no signal, which is the whole reason the cache exists —
/// pull to refresh is the only thing here that goes online.
final readerHouseholdsProvider = FutureProvider<List<Consumer>>((
  Ref ref,
) async {
  final firstLoad = awaitFirstRosterIfEmpty(ref);
  final user = await ref.watch(authControllerProvider.future);
  final areaId = user?.areaId;
  if (areaId == null) {
    throw const PermissionFailure(
      'This screen is for a meter reader, and no service area is attached to '
      'the account you are signed in with.',
    );
  }

  await firstLoad;
  final result = await ref.watch(consumerRepositoryProvider).areaRoster(areaId);
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
});

/// Meter Reader › Consumers.
///
/// A directory, not a work list: the round with its counters is the Readings
/// tab. This is for looking somebody up — the meter serial to check against
/// the one on the wall, and what the meter last read.
class ReaderConsumersScreen extends ConsumerStatefulWidget {
  const ReaderConsumersScreen({super.key});

  @override
  ConsumerState<ReaderConsumersScreen> createState() =>
      _ReaderConsumersScreenState();
}

class _ReaderConsumersScreenState extends ConsumerState<ReaderConsumersScreen> {
  final TextEditingController _search = TextEditingController();
  LocalNameSort _sort = LocalNameSort.az;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final households = ref.watch(readerHouseholdsProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Consumers')),
      body: SafeArea(
        child: households.when(
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
                ref.invalidate(readerHouseholdsProvider);
              },
            ),
          ),
          data: (List<Consumer> list) {
            final List<Consumer> visible =
                list
                    .where(
                      (Consumer household) =>
                          consumerMatchesSearch(household, _search.text),
                    )
                    .toList()
                  ..sort((a, b) {
                    final compared = a.fullName.toLowerCase().compareTo(
                      b.fullName.toLowerCase(),
                    );
                    return _sort == LocalNameSort.az ? compared : -compared;
                  });

            return RefreshIndicator(
              onRefresh: () async {
                final user = ref.read(authControllerProvider).value;
                final areaId = user?.areaId;
                if (areaId == null) return;

                // A refresh that fails is not worth an error screen: the reader
                // still has yesterday's list, which is worth far more than an
                // empty one. It is reported in passing and the cache stands.
                final result = await ref
                    .read(consumerRepositoryProvider)
                    .refreshAreaRoster(areaId);
                if (result case Err(:final failure)) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(failure.message)));
                  }
                }
                ref.invalidate(readerHouseholdsProvider);
              },
              child: list.isEmpty
                  ? ListView(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
                          child: Column(
                            children: <Widget>[
                              Icon(
                                Icons.people_outline,
                                size: 40,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No households on this phone yet.',
                                style: text.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pull down to fetch them while you have signal.',
                                style: text.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: LocalSearchField(
                                fieldKey: const ValueKey<String>(
                                  'reader-consumers-search',
                                ),
                                controller: _search,
                                onChanged: (_) => setState(() {}),
                                hintText:
                                    'Search name, account, purok or meter',
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: LocalSortButton<LocalNameSort>(
                                buttonKey: const ValueKey(
                                  'reader-consumers-sort',
                                ),
                                value: _sort,
                                options: localNameSortOptions,
                                onChanged: (value) =>
                                    setState(() => _sort = value),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _search.text.trim().isEmpty
                              ? '${list.length} household'
                                    '${list.length == 1 ? '' : 's'} in your area'
                              : '${visible.length} of ${list.length} households',
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 40),
                            child: Column(
                              children: <Widget>[
                                Icon(
                                  Icons.search_off,
                                  size: 40,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No household matches that search.',
                                  style: text.titleMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        else
                          for (
                            var index = 0;
                            index < visible.length;
                            index++
                          ) ...<Widget>[
                            _HouseholdTile(household: visible[index]),
                            if (index < visible.length - 1)
                              const SizedBox(height: 10),
                          ],
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// One household, drawn as a card that is plainly something to open: its own
/// surface, a ripple on tap, and a chevron pointing into its details.
class _HouseholdTile extends StatelessWidget {
  final Consumer household;

  const _HouseholdTile({required this.household});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String initials =
        '${household.firstName.isEmpty ? '' : household.firstName[0]}'
                '${household.lastName.isEmpty ? '' : household.lastName[0]}'
            .toUpperCase();
    final String identity = <String>[
      household.consumerNo.value,
      if (household.purok != null) household.purok!,
      if (household.meterSerialNo != null) household.meterSerialNo!,
    ].join(' · ');

    // Material rather than a decorated Container, so the ripple is drawn on
    // the card itself instead of underneath it.
    return Material(
      color: colours.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colours.outlineVariant),
      ),
      child: InkWell(
        onTap: () => showReaderHouseholdDetails(context, household),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colours.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  initials.isEmpty ? '?' : initials,
                  style: text.titleSmall?.copyWith(
                    color: colours.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      household.fullName,
                      style: text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      identity,
                      style: text.bodySmall?.copyWith(
                        color: colours.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.bolt_outlined,
                          size: 15,
                          color: colours.primary,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            household.previousReadingDate == null
                                ? 'No previous reading'
                                : '${household.previousReading.format()}'
                                      ' · read '
                                      '${_formatReadingDate(household.previousReadingDate!)}',
                            style: text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: colours.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatReadingDate(PhDate date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
