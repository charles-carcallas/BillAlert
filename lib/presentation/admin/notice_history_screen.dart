import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/supabase/failure_mapper.dart';
import '../common/local_search_field.dart';
import '../common/saved_list_time.dart';
import '../router.dart';
import 'disconnections_screen.dart';

class NoticeHistoryScreen extends ConsumerStatefulWidget {
  const NoticeHistoryScreen({super.key});
  @override
  ConsumerState<NoticeHistoryScreen> createState() =>
      _NoticeHistoryScreenState();
}

class _NoticeHistoryScreenState extends ConsumerState<NoticeHistoryScreen> {
  final _search = TextEditingController();
  String _outcome = 'all';
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Closed notice history')),
    body: Column(
      children: [
        const SavedListTime(cacheKey: 'notice-history', areaScoped: true),
        Padding(
          padding: const EdgeInsets.all(16),
          child: LocalSearchField(
            controller: _search,
            hintText: 'Search household or notice',
            onChanged: (_) => setState(() {}),
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final value in ['all', 'settled', 'cancelled', 'referred'])
              ChoiceChip(
                label: Text('${value[0].toUpperCase()}${value.substring(1)}'),
                selected: _outcome == value,
                onSelected: (_) => setState(() => _outcome = value),
              ),
          ],
        ),
        Expanded(
          child: ref
              .watch(closedNoticesProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) =>
                    Center(child: Text(FailureMapper.from(e, st).message)),
                data: (rows) {
                  final query = _search.text.trim().toLowerCase();
                  final visible = rows
                      .where(
                        (n) =>
                            (_outcome == 'all' || n.outcome.code == _outcome) &&
                            '${n.household} ${n.noticeNo}'
                                .toLowerCase()
                                .contains(query),
                      )
                      .toList();
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(closedNoticesProvider);
                      await ref.read(closedNoticesProvider.future);
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (visible.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No matching closed notices in this view.',
                            ),
                          ),
                        for (final n in visible)
                          ListTile(
                            title: Text('${n.household} · ${n.outcome.code}'),
                            subtitle: Text(
                              '${n.noticeNo}\nClosed ${n.closedAt.toUtc().add(const Duration(hours: 8))} PH\nBy ${n.closedBy ?? 'Not recorded'}\n${n.notes ?? 'No notes recorded'}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(
                              Routes.noticeDocumentFor(n.id.value),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
        ),
      ],
    ),
  );
}
