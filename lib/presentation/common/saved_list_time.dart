import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

final savedListTimeProvider = StreamProvider.family<DateTime?, String>((
  ref,
  key,
) {
  ref.watch(authControllerProvider);
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.cachedQueries)..where((t) => t.queryKey.equals(key)))
      .watchSingleOrNull()
      .map((row) => row == null ? null : DateTime.tryParse(row.savedAt));
});

class SavedListTime extends ConsumerWidget {
  final String cacheKey;
  final bool areaScoped;
  final bool compact;
  const SavedListTime({
    required this.cacheKey,
    this.areaScoped = false,
    this.compact = false,
    super.key,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final area = ref.watch(authControllerProvider).value?.areaId?.value;
    final saved = ref.watch(
      savedListTimeProvider(areaScoped ? '$cacheKey:$area' : cacheKey),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: saved.when(
        loading: () => compact
            ? const SizedBox.shrink()
            : const Text('Checking saved copy…'),
        error: (_, _) => const Text('Saved-copy time could not be checked.'),
        data: (time) {
          final ph = time?.toUtc().add(const Duration(hours: 8));
          if (compact) {
            if (ph == null) return const SizedBox.shrink();
            final now = DateTime.now().toUtc().add(const Duration(hours: 8));
            final today =
                ph.year == now.year &&
                ph.month == now.month &&
                ph.day == now.day;
            final hour = ph.hour % 12 == 0 ? 12 : ph.hour % 12;
            final clock =
                '$hour:${ph.minute.toString().padLeft(2, '0')} ${ph.hour < 12 ? 'AM' : 'PM'}';
            final date = today ? '' : '${ph.month}/${ph.day}/${ph.year} · ';
            return Tooltip(
              message:
                  'Saved copy · Philippine time. Refresh online for changes.',
              child: Text(
                'Updated $date$clock',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }
          return Text(
            ph == null
                ? 'No saved copy confirmed on this phone.'
                : 'Saved ${ph.year}-${ph.month.toString().padLeft(2, '0')}-${ph.day.toString().padLeft(2, '0')} '
                      '${ph.hour.toString().padLeft(2, '0')}:${ph.minute.toString().padLeft(2, '0')} PH · Refresh online for changes.',
            style: Theme.of(context).textTheme.bodySmall,
          );
        },
      ),
    );
  }
}
