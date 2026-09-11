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
import '../common/failure_banner.dart';
import '../providers.dart';

/// The households of this reader's area, from the encrypted cache.
///
/// Reads the cache, not the network. The meter reader opens this standing in
/// a barangay with no signal, which is the whole reason the cache exists —
/// pull to refresh is the only thing here that goes online.
final readerHouseholdsProvider = FutureProvider<List<Consumer>>((
  Ref ref,
) async {
  final user = await ref.watch(authControllerProvider.future);
  final areaId = user?.areaId;
  if (areaId == null) {
    throw const PermissionFailure(
      'This screen is for a meter reader, and no service area is attached to '
      'the account you are signed in with.',
    );
  }

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
class ReaderConsumersScreen extends ConsumerWidget {
  const ReaderConsumersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onRetry: () => ref.invalidate(readerHouseholdsProvider),
            ),
          ),
          data: (List<Consumer> list) => RefreshIndicator(
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
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: list.length + 1,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${list.length} household'
                            '${list.length == 1 ? '' : 's'} in your area',
                            style: text.titleSmall,
                          ),
                        );
                      }
                      return _HouseholdTile(household: list[index - 1]);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _HouseholdTile extends StatelessWidget {
  final Consumer household;

  const _HouseholdTile({required this.household});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(household.fullName, style: text.titleMedium),
      subtitle: Text(
        <String>[
          household.consumerNo.value,
          if (household.purok != null) household.purok!,
          if (household.meterSerialNo != null) household.meterSerialNo!,
        ].join(' · '),
        style: text.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Text(household.previousReading.format(), style: text.bodyLarge),
          Text(
            household.previousReadingDate == null
                ? 'No previous reading'
                : 'Last read ${_formatReadingDate(household.previousReadingDate!)}',
            style: text.bodySmall,
          ),
        ],
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
