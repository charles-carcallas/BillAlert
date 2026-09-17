import 'package:flutter/material.dart';
// `Consumer` here means a household, not Riverpod's widget.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../domain/entities/consumer.dart';
import '../common/failure_banner.dart';
import '../common/local_sort_button.dart';
import 'serve_notice_controller.dart';

/// DOM-05 — Admin › serve a disconnection notice.
///
/// Two steps: choose the household, then confirm with an optional reason.
/// Confirmation is deliberate and separate — serving a notice starts a legal
/// clock against somebody's electricity, and it should not be one tap away
/// from a list.
///
/// The moment of service is stamped here, on this device, and the 48-hour
/// period runs from it. It is NOT the moment this reaches the server: a
/// notice served on a Friday afternoon with no signal would otherwise give
/// the household less time than the law allows.
class ServeNoticeScreen extends ConsumerStatefulWidget {
  const ServeNoticeScreen({super.key});

  @override
  ConsumerState<ServeNoticeScreen> createState() => _ServeNoticeScreenState();
}

class _ServeNoticeScreenState extends ConsumerState<ServeNoticeScreen> {
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serveNoticeControllerProvider);
    final controller = ref.read(serveNoticeControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;

    if (state.servedTo != null) {
      return _Served(
        name: state.servedTo!,
        onDone: () => Navigator.of(context).maybePop(),
      );
    }

    final Consumer? chosen = state.selected;

    return Scaffold(
      appBar: AppBar(
        title: Text(chosen == null ? 'Serve a notice' : 'Confirm notice'),
        leading: chosen == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: controller.clearSelection,
              ),
      ),
      body: SafeArea(
        child: chosen == null
            ? _Picker(state: state, controller: controller)
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'SERVING NOTICE TO',
                          style: text.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(chosen.fullName, style: text.titleLarge),
                        Text(
                          '${chosen.consumerNo.value}'
                          '${chosen.purok == null ? '' : ' · ${chosen.purok}'}',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),

                  if (state.failure != null) ...<Widget>[
                    const SizedBox(height: 12),
                    FailureBanner(failure: state.failure!),
                  ],

                  const SizedBox(height: 20),
                  Text('Reason (optional)', style: text.titleSmall),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _reason,
                    enabled: !state.isSubmitting,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      hintText: 'Recorded on the notice, in your own words.',
                    ),
                  ),

                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.35),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.35),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'Serving this notice starts the notice period now. '
                        'The earliest lawful disconnection is worked out by '
                        'the server from this moment — 48 hours, then past '
                        'any Sunday or holiday.',
                        style: text.bodySmall,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: state.isSubmitting
                        ? null
                        : () => _confirm(controller),
                    child: state.isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Serve notice'),
                  ),
                ],
              ),
      ),
    );
  }

  /// One more deliberate step. The list is for finding somebody; this is for
  /// meaning it.
  Future<void> _confirm(ServeNoticeController controller) async {
    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Serve this notice?'),
        content: const Text(
          'The household is warned that their supply may be disconnected, '
          'and the notice period starts now. This cannot be undone from the '
          'app — a served notice is closed, not deleted.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Serve notice'),
          ),
        ],
      ),
    );

    if (sure ?? false) {
      await controller.serve(reason: _reason.text);
    }
  }
}

enum _ServeSort { eligibleFirst, nameAz, nameZa }

class _Picker extends StatefulWidget {
  final ServeNoticeState state;
  final ServeNoticeController controller;

  const _Picker({required this.state, required this.controller});

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  _ServeSort _sort = _ServeSort.eligibleFirst;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final state = widget.state;
    final controller = widget.controller;
    final List<Consumer> visible = List.of(state.visible);
    if (_sort != _ServeSort.eligibleFirst) {
      visible.sort(
        (a, b) => compareNames(
          a.fullName,
          b.fullName,
          _sort == _ServeSort.nameAz ? LocalNameSort.az : LocalNameSort.za,
        ),
      );
    }

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  onChanged: controller.search,
                  decoration: const InputDecoration(
                    hintText: 'Search name or account number',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 132,
                child: LocalSortButton<_ServeSort>(
                  buttonKey: const ValueKey('serve-notice-sort'),
                  value: _sort,
                  options: const <LocalSortOption<_ServeSort>>[
                    LocalSortOption(
                      value: _ServeSort.eligibleFirst,
                      label: 'Eligible',
                      icon: Icons.priority_high,
                    ),
                    LocalSortOption(
                      value: _ServeSort.nameAz,
                      label: 'Name A–Z',
                      icon: Icons.sort_by_alpha,
                    ),
                    LocalSortOption(
                      value: _ServeSort.nameZa,
                      label: 'Name Z–A',
                      icon: Icons.sort_by_alpha,
                    ),
                  ],
                  onChanged: (value) => setState(() => _sort = value),
                ),
              ),
            ],
          ),
        ),
        if (state.failure != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: FailureBanner(
              failure: state.failure!,
              onRetry: controller.refreshFromServer,
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Only households with an overdue bill can be served. '
                    'Eligible households are listed first.',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: state.isLoading && state.households.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: controller.refreshFromServer,
                  child: visible.isEmpty
                      ? ListView(
                          children: <Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                32,
                                64,
                                32,
                                32,
                              ),
                              child: Text(
                                state.households.isEmpty
                                    ? 'No households on this device yet. Pull '
                                          'down to fetch them.'
                                    : 'No household matches that search.',
                                style: text.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (BuildContext context, int index) {
                            final Consumer c = visible[index];
                            final int overdue = state.overdueCountFor(c);
                            // The server refuses a household with nothing
                            // overdue, and refuses an inactive account. Both
                            // are shown here rather than discovered by being
                            // told no after choosing a name.
                            final bool allowed = state.canServe(c);

                            return Container(
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLowest,
                                border: Border.all(
                                  color: allowed
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant
                                      : Theme.of(context)
                                            .colorScheme
                                            .outlineVariant
                                            .withValues(alpha: 0.55),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: ListTile(
                                title: Text(
                                  c.fullName,
                                  style: text.titleMedium,
                                ),
                                subtitle: Text(
                                  <String>[
                                    c.consumerNo.value,
                                    if (c.purok != null) c.purok!,
                                    if (!c.isActive)
                                      'not an active account'
                                    else if (overdue == 0)
                                      'nothing overdue'
                                    else
                                      '$overdue overdue bill'
                                          '${overdue == 1 ? '' : 's'}',
                                  ].join(' · '),
                                  style: text.bodySmall,
                                ),
                                trailing: allowed
                                    ? const Icon(Icons.chevron_right)
                                    : null,
                                enabled: allowed,
                                onTap: () => controller.select(c),
                              ),
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

class _Served extends StatelessWidget {
  final String name;
  final VoidCallback onDone;

  const _Served({required this.name, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Notice served')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 24),
              Icon(
                Icons.check_circle_outline,
                size: 44,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Notice served to $name',
                style: text.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'It now appears under Notices with the time remaining. The '
                'household has been told.',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              FilledButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}
