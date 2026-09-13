import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../auth/auth_controller.dart';
import '../common/failure_banner.dart';
import '../common/local_search_field.dart';
import '../common/notice_search.dart';
import '../common/staff_app_bar.dart';
import '../providers.dart';
import '../router.dart';

/// Active disconnection notices for this Admin's area.
final activeNoticesProvider = FutureProvider<List<ActiveNotice>>((
  Ref ref,
) async {
  final user = await ref.watch(authControllerProvider.future);
  final areaId = user?.areaId;
  if (areaId == null) {
    throw const PermissionFailure(
      'This screen is for an Area President, and no service area is attached '
      'to the account you are signed in with.',
    );
  }

  final result = await ref.watch(noticeRepositoryProvider).activeFor(areaId);
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
});

/// DOM-05 — Admin › Notices.
///
/// Every notice served in this area that is still inside its period, oldest
/// first, with how long is left before disconnection would be lawful.
///
/// That countdown is not calculated here. `fn_earliest_lawful_disconnection`
/// works it out server-side — 48 hours from the moment the notice was SERVED,
/// then advanced past Sundays and holidays — and this screen only counts down
/// to the answer it was given. A second opinion about a legal deadline is the
/// last thing this app should hold.
class DisconnectionsScreen extends ConsumerStatefulWidget {
  const DisconnectionsScreen({super.key});

  @override
  ConsumerState<DisconnectionsScreen> createState() =>
      _DisconnectionsScreenState();
}

enum _NoticeFilter { all, elapsed }

class _DisconnectionsScreenState extends ConsumerState<DisconnectionsScreen> {
  _NoticeFilter _filter = _NoticeFilter.all;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notices = ref.watch(activeNoticesProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const StaffAppBar(title: 'Disconnections'),
      floatingActionButton: FloatingActionButton.extended(
        // `push`, so the back arrow returns to this list, and the list
        // refreshes when the notice lands.
        onPressed: () async {
          await context.push(Routes.serveNotice);
          ref.invalidate(activeNoticesProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('Serve a notice'),
      ),
      body: SafeArea(
        child: notices.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => Padding(
            padding: const EdgeInsets.all(16),
            child: FailureBanner(
              failure: error is AppFailure
                  ? error
                  : ServerFailure(ServerFailure.defaultMessage, '$error'),
              onRetry: () => ref.invalidate(activeNoticesProvider),
            ),
          ),
          data: (List<ActiveNotice> list) {
            final int elapsedCount = list
                .where((ActiveNotice notice) => notice.periodElapsed)
                .length;
            final String query = _search.text.trim();
            final visible = list.where((ActiveNotice notice) {
              final bool matchesFilter =
                  _filter == _NoticeFilter.all || notice.periodElapsed;
              if (!matchesFilter) return false;
              return noticeMatchesSearch(notice, query);
            }).toList();
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(activeNoticesProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: <Widget>[
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: Column(
                        children: <Widget>[
                          Icon(
                            Icons.verified_outlined,
                            size: 40,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No active notices.',
                            style: text.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Nobody in this area is under a disconnection '
                            'notice.',
                            style: text.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else ...<Widget>[
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: '${list.length}',
                            style: text.headlineMedium,
                          ),
                          TextSpan(
                            text: ' awaiting review',
                            style: text.bodyMedium,
                          ),
                          if (elapsedCount > 0)
                            TextSpan(
                              text: '  ·  $elapsedCount past 48h',
                              style: text.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    LocalSearchField(
                      fieldKey: const ValueKey<String>('admin-notices-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      hintText: 'Search consumer, account or notice number',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _filter == _NoticeFilter.all,
                          onSelected: (_) =>
                              setState(() => _filter = _NoticeFilter.all),
                        ),
                        ChoiceChip(
                          label: const Text('Past 48h'),
                          selected: _filter == _NoticeFilter.elapsed,
                          onSelected: (_) =>
                              setState(() => _filter = _NoticeFilter.elapsed),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (visible.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Text(
                          query.isEmpty
                              ? 'No notices match this filter.'
                              : 'No notice matches that search and filter.',
                          style: text.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final ActiveNotice notice in visible)
                      _NoticeTile(
                        notice: notice,
                        // Returning from the document refreshes the list: a
                        // notice closed in there is no longer active, and it
                        // must not linger here looking as though it were.
                        onOpen: () async {
                          await context.push(
                            Routes.noticeDocumentFor(notice.id.value),
                          );
                          ref.invalidate(activeNoticesProvider);
                        },
                      ),
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

class _NoticeTile extends StatelessWidget {
  final ActiveNotice notice;
  final VoidCallback onOpen;

  const _NoticeTile({required this.notice, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool elapsed = notice.periodElapsed;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(
          color: elapsed ? colours.error : colours.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: elapsed ? colours.error : colours.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(notice.consumerLabel, style: text.titleMedium),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colours.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      elapsed
                          ? '48h elapsed'
                          : '${notice.hoursRemaining}h left',
                      style: text.bodySmall?.copyWith(
                        color: colours.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${notice.noticeNo} · Served ${_servedOn(notice.servedAt)}',
                style: text.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                elapsed
                    ? 'The notice period has passed. Disconnection may now be '
                          'referred to the cooperative.'
                    : 'Disconnection is not lawful until the period is over.',
                style: text.bodySmall,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colours.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The Philippine calendar date the notice was served. `served_at` is the
  /// moment of service in the field, not of sync, and the whole period is
  /// counted from it.
  static String _servedOn(DateTime instant) {
    final PhDate day = PhDate.at(instant);
    const List<String> months = <String>[
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
    return '${day.day} ${months[day.month - 1]} ${day.year}';
  }
}
