import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/repositories/notice_repository.dart';
import '../../domain/value_objects/ph_date.dart';
import '../auth/auth_controller.dart';
import '../common/failure_banner.dart';
import '../providers.dart';

/// Active disconnection notices for this Admin's area.
final activeNoticesProvider = FutureProvider<List<ActiveNotice>>((Ref ref) async {
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
class DisconnectionsScreen extends ConsumerWidget {
  const DisconnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(activeNoticesProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Notices')),
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
          data: (List<ActiveNotice> list) => RefreshIndicator(
            onRefresh: () async => ref.invalidate(activeNoticesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: <Widget>[
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 64),
                    child: Column(
                      children: <Widget>[
                        Icon(
                          Icons.verified_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                  Text(
                    '${list.length} active notice'
                    '${list.length == 1 ? '' : 's'}',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final ActiveNotice notice in list)
                    _NoticeTile(notice: notice),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  final ActiveNotice notice;

  const _NoticeTile({required this.notice});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool elapsed = notice.hoursRemaining == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(notice.consumerLabel, style: text.titleMedium),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colours.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    elapsed
                        ? 'period elapsed'
                        : '${notice.hoursRemaining}h left',
                    style: text.bodySmall
                        ?.copyWith(color: colours.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Served ${_servedOn(notice.servedAt)}',
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
          ],
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${day.day} ${months[day.month - 1]} ${day.year}';
  }
}
