import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/bill_repository.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../common/staff_app_bar.dart';
import 'post_bill_amount_controller.dart';

/// FR-21b — Admin › Amounts.
///
/// The Area President types in the peso figure the cooperative returned.
/// Nothing on this screen calculates it: there is no tariff and no rate
/// table in BillAlert, and any multiplication that produced pesos here would
/// be a misunderstanding of the whole domain.
///
/// The consumption sits directly above the amount box on purpose. The
/// likeliest error in the system is a transcription typo, and ₱6,583.00 next
/// to "58 kWh" looks wrong in a way that ₱6,583.00 on its own does not.
class PostBillAmountScreen extends ConsumerStatefulWidget {
  const PostBillAmountScreen({super.key});

  @override
  ConsumerState<PostBillAmountScreen> createState() =>
      _PostBillAmountScreenState();
}

class _PostBillAmountScreenState extends ConsumerState<PostBillAmountScreen> {
  final TextEditingController _search = TextEditingController();

  /// Which queue row is open. One at a time: the form is long, and the Admin
  /// is working one statement at a time anyway.
  String? _expandedBillId;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(postBillAmountControllerProvider);
    final controller = ref.read(postBillAmountControllerProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;
    final List<AwaitingAmountEntry> visibleQueue = _matchingEntries(
      state.queue,
      _search.text,
    );

    return Scaffold(
      appBar: const StaffAppBar(title: 'Post bill amount'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: controller.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _Header(
                count: state.queue.length,
                cycleLabel: _cycleLabel(state),
              ),

              if (state.failure != null) ...<Widget>[
                const SizedBox(height: 12),
                FailureBanner(
                  failure: state.failure!,
                  onRetry: controller.refresh,
                ),
              ],

              if (state.postedMessage != null) ...<Widget>[
                const SizedBox(height: 12),
                _PostedNotice(message: state.postedMessage!),
              ],

              const SizedBox(height: 16),

              if (state.queue.isNotEmpty) ...<Widget>[
                TextField(
                  key: const ValueKey<String>('amounts-search'),
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Search readings',
                    hintText: 'Name, consumer number, purok or bill number',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
              ],

              if (state.isLoading && state.queue.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.queue.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.done_all,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Nothing waiting for an amount.',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Every reading in this area has been priced.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else if (visibleQueue.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.search_off,
                        size: 40,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No matching readings.',
                        style: text.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try another name, consumer number, purok or bill '
                        'number.',
                        style: text.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                for (final AwaitingAmountEntry entry in visibleQueue)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _QueueCard(
                      entry: entry,
                      isExpanded: _expandedBillId == entry.bill.id.value,
                      isPosting: state.posting == entry.bill.id,
                      onToggle: () => setState(() {
                        _expandedBillId = _expandedBillId == entry.bill.id.value
                            ? null
                            : entry.bill.id.value;
                      }),
                      onPost: (String amountText, PhDate? dueDate) =>
                          controller.post(
                            entry: entry,
                            amountText: amountText,
                            dueDate: dueDate,
                          ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  /// The cycle every row in the queue belongs to. Taken from the rows rather
  /// than from the clock, so it says what is actually on screen.
  static String? _cycleLabel(PostBillAmountState state) =>
      state.queue.isEmpty ? null : state.queue.first.bill.cycle.displayName;

  /// Searches only the real queue already returned for this Admin's area.
  /// It never fabricates rows and does not issue a second server query.
  static List<AwaitingAmountEntry> _matchingEntries(
    List<AwaitingAmountEntry> queue,
    String rawQuery,
  ) {
    final String query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return queue;

    return queue
        .where((AwaitingAmountEntry entry) {
          final String searchable = <String>[
            entry.consumerName,
            entry.consumerNo.value,
            entry.purok ?? '',
            entry.bill.billNo.value,
          ].join(' ').toLowerCase();
          return searchable.contains(query);
        })
        .toList(growable: false);
  }
}

class _Header extends StatelessWidget {
  final int count;
  final String? cycleLabel;

  const _Header({required this.count, this.cycleLabel});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    final colours = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (cycleLabel != null)
            Text(
              cycleLabel!.toUpperCase(),
              style: text.labelSmall?.copyWith(
                color: colours.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(text: '$count', style: text.headlineMedium),
                TextSpan(
                  text: ' reading${count == 1 ? '' : 's'} awaiting an amount',
                  style: text.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Transcribe the amount and the due date from what the cooperative '
            'returned. BillAlert does not calculate either one.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _PostedNotice extends StatelessWidget {
  final String message;

  const _PostedNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colours.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle_outline, color: colours.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colours.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// One household waiting for a figure.
class _QueueCard extends StatefulWidget {
  final AwaitingAmountEntry entry;
  final bool isExpanded;
  final bool isPosting;
  final VoidCallback onToggle;
  final void Function(String amountText, PhDate? dueDate) onPost;

  const _QueueCard({
    required this.entry,
    required this.isExpanded,
    required this.isPosting,
    required this.onToggle,
    required this.onPost,
  });

  @override
  State<_QueueCard> createState() => _QueueCardState();
}

class _QueueCardState extends State<_QueueCard> {
  final TextEditingController _amount = TextEditingController();
  PhDate? _dueDate;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AwaitingAmountEntry entry = widget.entry;
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(
          color: widget.isExpanded ? colours.primary : colours.outlineVariant,
          width: widget.isExpanded ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: widget.onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: entry.daysWaiting <= 0
                          ? colours.primaryContainer
                          : const Color(0xFFAE6900),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                entry.consumerName,
                                style: text.titleMedium,
                              ),
                            ),
                            _WaitBadge(label: entry.waitLabel),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(entry.consumerNo.value, style: text.bodySmall),
                        const SizedBox(height: 6),
                        Text(
                          '${entry.previousReading.format()} → '
                          '${entry.currentReading.format()}',
                          style: text.bodySmall,
                        ),
                        Text(
                          '${entry.bill.consumption.format()} · read '
                          '${_shortDate(entry.readingDate)}',
                          style: text.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: colours.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (widget.isExpanded) ...<Widget>[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ReadingDetail(entry: entry),
                  const SizedBox(height: 8),
                  Text(
                    'Consumption is shown so a wildly wrong amount is obvious.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 16),

                  Text('Amount due', style: text.titleSmall),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _amount,
                    enabled: !widget.isPosting,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    // Money is parsed from this text, never from a double, so
                    // the field only needs to let the digits and one point
                    // through.
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: const InputDecoration(
                      prefixText: '₱ ',
                      hintText: '0.00',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  Text('Due date', style: text.titleSmall),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: widget.isPosting ? null : _pickDueDate,
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _dueDate == null
                          ? 'Choose the date on the statement'
                          : _longDate(_dueDate!),
                    ),
                  ),
                  const SizedBox(height: 20),

                  FilledButton(
                    onPressed: widget.isPosting ? null : _submit,
                    child: widget.isPosting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_buttonLabel()),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Posting sends the consumer's bill-ready alert "
                    'automatically.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "Post · ₱658.30" once the amount reads as money, so the figure is
  /// repeated back before it is committed. Money.tryParse decides — the same
  /// parser the controller uses, so the button cannot promise something the
  /// controller would then reject.
  String _buttonLabel() {
    final Money? amount = Money.tryParse(_amount.text);
    return amount == null ? 'Post amount' : 'Post · ${amount.format()}';
  }

  Future<void> _pickDueDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate == null
          ? now.add(const Duration(days: 14))
          : DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day),
      // A due date in the past is refused by fn_post_bill_amount, so the
      // picker does not offer one.
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() => _dueDate = PhDate(picked.year, picked.month, picked.day));
    }
  }

  void _submit() => widget.onPost(_amount.text, _dueDate);

  static const List<String> _months = <String>[
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

  static String _shortDate(PhDate date) =>
      '${date.day} ${_months[date.month - 1]}';

  static String _longDate(PhDate date) =>
      '${date.day} ${_months[date.month - 1]} ${date.year}';
}

class _WaitBadge extends StatelessWidget {
  final String label;

  const _WaitBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colours.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: colours.onSurfaceVariant),
      ),
    );
  }
}

/// Previous, present, consumption and the date read — the four figures that
/// let the Admin check the statement in front of them against the meter.
class _ReadingDetail extends StatelessWidget {
  final AwaitingAmountEntry entry;

  const _ReadingDetail({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _Fact(
                  term: 'Previous',
                  value: entry.previousReading.format(),
                ),
              ),
              Expanded(
                child: _Fact(
                  term: 'Present',
                  value: entry.currentReading.format(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _Fact(
                  term: 'Consumption',
                  value: entry.bill.consumption.format(),
                  emphasise: true,
                ),
              ),
              Expanded(
                child: _Fact(
                  term: 'Read on',
                  value: _QueueCardState._shortDate(entry.readingDate),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String term;
  final String value;
  final bool emphasise;

  const _Fact({
    required this.term,
    required this.value,
    this.emphasise = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(term, style: text.bodySmall),
        const SizedBox(height: 2),
        Text(value, style: emphasise ? text.titleMedium : text.bodyLarge),
      ],
    );
  }
}
