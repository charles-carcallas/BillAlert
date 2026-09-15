import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/bill_repository.dart';
import '../../domain/value_objects/kwh.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../common/failure_banner.dart';
import '../common/staff_app_bar.dart';
import 'post_bill_amount_controller.dart';

/// FR-21b — Admin › Amounts.
///
/// The Area President types in the peso figure the cooperative returned.
/// Nothing on this screen calculates it: there is no tariff and no rate
/// table in BillAlert. The one adjustment is the required whole-peso ceiling:
/// any amount with centavos is rounded up before it is posted.
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

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(postBillAmountControllerProvider);
    final controller = ref.read(postBillAmountControllerProvider.notifier);
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
                const SizedBox(height: 14),
                _QueueCaption(
                  showing: visibleQueue.length,
                  total: state.queue.length,
                  isFiltered: _search.text.trim().isNotEmpty,
                ),
                const SizedBox(height: 8),
              ],

              if (state.isLoading && state.queue.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.queue.isEmpty)
                const _EmptyState(
                  icon: Icons.done_all,
                  title: 'Nothing waiting for an amount.',
                  message: 'Every reading in this area has been priced.',
                )
              else if (visibleQueue.isEmpty)
                const _EmptyState(
                  icon: Icons.search_off,
                  title: 'No matching readings.',
                  message:
                      'Try another name, consumer number, purok or bill '
                      'number.',
                )
              else
                for (final AwaitingAmountEntry entry in visibleQueue)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _QueueCard(
                      entry: entry,
                      isPosting: state.posting == entry.bill.id,
                      onTap: () => _openAmount(entry),
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

  Future<void> _openAmount(AwaitingAmountEntry entry) async {
    ref.read(postBillAmountControllerProvider.notifier).dismissMessages();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // Close/back goes through the draft guard; a drag or outside tap must
      // never silently throw away a cooperative amount.
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _AmountSheet(entry: entry),
    );
  }

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

/// Figures line up in columns, so 4,610 and 4,668 can be compared at a glance.
const List<FontFeature> _tabularFigures = <FontFeature>[
  FontFeature.tabularFigures(),
];

const List<String> _months = <String>[
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

String _shortDate(PhDate date) => '${date.day} ${_months[date.month - 1]}';

String _longDate(PhDate date) =>
    '${date.day} ${_months[date.month - 1]} ${date.year}';

/// "4,610.00" — a reading without its unit, for "4,610.00 → 4,668.00".
String _bareKwh(Kwh reading) => reading.format().replaceFirst(' kWh', '');

/// "2020-0791-TUB · Purok 3", or just the number when no purok is on file.
String _identity(AwaitingAmountEntry entry) {
  final String? purok = entry.purok?.trim();
  return purok == null || purok.isEmpty
      ? entry.consumerNo.value
      : '${entry.consumerNo.value} · $purok';
}

/// Today's readings in the brand green; anything older in amber, so the eye
/// goes first to the households that have waited longest.
({Color foreground, Color background}) _waitTone(
  BuildContext context,
  int daysWaiting,
) {
  final ColorScheme colours = Theme.of(context).colorScheme;
  if (daysWaiting <= 0) {
    return (
      foreground: colours.primary,
      background: colours.primary.withValues(alpha: 0.12),
    );
  }
  final bool dark = colours.brightness == Brightness.dark;
  final Color amber = dark ? const Color(0xFFF2B866) : const Color(0xFF8A5100);
  return (
    foreground: amber,
    background: amber.withValues(alpha: dark ? 0.18 : 0.12),
  );
}

class _Header extends StatelessWidget {
  final int count;
  final String? cycleLabel;

  const _Header({required this.count, this.cycleLabel});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (cycleLabel != null) ...<Widget>[
            Text(
              cycleLabel!.toUpperCase(),
              style: text.labelSmall?.copyWith(
                color: colours.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                '$count',
                style: text.headlineMedium?.copyWith(
                  fontSize: 32,
                  height: 1.2,
                  fontFeatures: _tabularFigures,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'reading${count == 1 ? '' : 's'} awaiting an amount',
                  style: text.titleSmall?.copyWith(
                    color: colours.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Copy the amount and due date from the cooperative's statement — "
            'BillAlert never calculates them. Posting alerts the household in '
            'the app and by text.',
            style: text.bodyMedium,
          ),
        ],
      ),
    );
  }
}

/// "Longest waiting first", and how many rows a search is showing.
class _QueueCaption extends StatelessWidget {
  final int showing;
  final int total;
  final bool isFiltered;

  const _QueueCaption({
    required this.showing,
    required this.total,
    required this.isFiltered,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle? style = Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
    );

    return Row(
      children: <Widget>[
        Expanded(child: Text('LONGEST WAITING FIRST', style: style)),
        if (isFiltered) Text('$showing of $total', style: style),
      ],
    );
  }
}

class _PostedNotice extends StatelessWidget {
  final String message;

  const _PostedNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;

    // A tint with dark text rather than white on green: white on the brand's
    // lighter green does not reach WCAG AA contrast for text this size.
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colours.primary.withValues(alpha: 0.10),
          border: Border.all(color: colours.primary.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colours.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, size: 20, color: colours.onPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colours.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colours.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: colours.primary),
          ),
          const SizedBox(height: 14),
          Text(title, style: text.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// One household waiting for a figure, in the queue.
class _QueueCard extends StatelessWidget {
  final AwaitingAmountEntry entry;
  final bool isPosting;
  final VoidCallback onTap;

  const _QueueCard({
    required this.entry,
    required this.isPosting,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final Color waitColour = _waitTone(context, entry.daysWaiting).foreground;

    // Material rather than a decorated Container, so the ripple is drawn on
    // the card itself instead of underneath it where nobody can see it.
    return Material(
      color: colours.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colours.outlineVariant),
      ),
      child: InkWell(
        onTap: isPosting ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: waitColour,
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
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _WaitBadge(entry: entry),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _identity(entry),
                      style: text.bodySmall?.copyWith(
                        fontFeatures: _tabularFigures,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: entry.bill.consumption.format(),
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(
                            text:
                                '  ·  ${_bareKwh(entry.previousReading)} → '
                                '${_bareKwh(entry.currentReading)}  ·  read '
                                '${_shortDate(entry.readingDate)}',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                      style: const TextStyle(fontFeatures: _tabularFigures),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 32,
                height: 24,
                child: Center(
                  child: isPosting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.chevron_right,
                          color: colours.onSurfaceVariant,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountSheet extends ConsumerStatefulWidget {
  final AwaitingAmountEntry entry;

  const _AmountSheet({required this.entry});

  @override
  ConsumerState<_AmountSheet> createState() => _AmountSheetState();
}

class _AmountSheetState extends ConsumerState<_AmountSheet> {
  bool _dirty = false;
  bool _posting = false;
  bool _confirmingClose = false;

  @override
  Widget build(BuildContext context) {
    final failure = ref.watch(postBillAmountControllerProvider).failure;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Post bill amount',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close amount form',
                      onPressed: _posting ? null : _close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (failure != null) ...<Widget>[
                        const SizedBox(height: 4),
                        FailureBanner(failure: failure),
                      ],
                      const SizedBox(height: 8),
                      _AmountForm(
                        entry: widget.entry,
                        isPosting: _posting,
                        onDirtyChanged: (dirty) => _dirty = dirty,
                        onPost: _post,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _close() async {
    if (_posting || _confirmingClose) return;
    if (_dirty) {
      _confirmingClose = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard entered amount?'),
          content: const Text(
            'This amount and due date have not been posted or saved. Keep editing to finish the bill.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      _confirmingClose = false;
      if (!mounted || discard != true) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _post(String amountText, PhDate? dueDate) async {
    if (_posting) return;
    setState(() => _posting = true);
    await ref
        .read(postBillAmountControllerProvider.notifier)
        .post(entry: widget.entry, amountText: amountText, dueDate: dueDate);
    if (!mounted) return;
    if (ref.read(postBillAmountControllerProvider).postedMessage != null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _posting = false);
    }
  }
}

/// The household, its reading, and the two figures copied from the
/// cooperative statement.
class _AmountForm extends StatefulWidget {
  final AwaitingAmountEntry entry;
  final bool isPosting;
  final void Function(String amountText, PhDate? dueDate) onPost;
  final ValueChanged<bool> onDirtyChanged;

  const _AmountForm({
    required this.entry,
    required this.isPosting,
    required this.onPost,
    required this.onDirtyChanged,
  });

  @override
  State<_AmountForm> createState() => _AmountFormState();
}

class _AmountFormState extends State<_AmountForm> {
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

    // Large, because this is the one number typed by hand from paper.
    final TextStyle amountStyle = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      color: colours.onSurface,
      fontFeatures: _tabularFigures,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(entry.consumerName, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(
                    _identity(entry),
                    style: text.bodySmall?.copyWith(
                      fontFeatures: _tabularFigures,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _WaitBadge(entry: entry),
          ],
        ),
        const SizedBox(height: 12),
        _ReadingDetail(entry: entry),
        const SizedBox(height: 20),

        Text('Amount due', style: text.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          enabled: !widget.isPosting,
          style: amountStyle,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // Money is parsed from this text, never from a double, so the field
          // only needs to let the digits and one point through.
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            prefixText: '₱ ',
            prefixStyle: amountStyle.copyWith(color: colours.onSurfaceVariant),
            hintText: '0.00',
            hintStyle: amountStyle.copyWith(
              color: colours.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          onChanged: (_) {
            setState(() {});
            _reportDirty();
          },
        ),
        const SizedBox(height: 6),
        Text(
          'Any centavos are always rounded up to the next peso.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 20),

        Text('Due date', style: text.titleSmall),
        const SizedBox(height: 8),
        _DueDateField(
          dueDate: _dueDate,
          enabled: !widget.isPosting,
          onTap: _pickDueDate,
        ),
        const SizedBox(height: 24),

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
          "Posting sends the consumer's bill-ready alert in the app and by "
          'text, automatically.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// "Review · ₱659.00" once the amount reads as money, so the figure is
  /// repeated back before it is committed. Money.tryParse decides — the same
  /// parser the controller uses, so the button cannot promise something the
  /// controller would then reject.
  String _buttonLabel() {
    final Money? amount = Money.tryParse(_amount.text);
    if (amount == null) return 'Review amount';
    final Money rounded = amount.roundUpToWholePeso();
    return amount == rounded
        ? 'Review · ${rounded.format()}'
        : 'Review · ${rounded.format()} (rounded up)';
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

    if (picked != null && mounted) {
      setState(() => _dueDate = PhDate(picked.year, picked.month, picked.day));
      _reportDirty();
    }
  }

  void _reportDirty() =>
      widget.onDirtyChanged(_amount.text.isNotEmpty || _dueDate != null);

  Future<void> _submit() async {
    final Money? enteredAmount = Money.tryParse(_amount.text);
    final PhDate? dueDate = _dueDate;

    // Keep validation in the controller/use case. Sending invalid input there
    // produces the existing FailureBanner instead of opening a confirmation
    // dialog that cannot show trustworthy values.
    if (enteredAmount == null || dueDate == null) {
      widget.onPost(_amount.text, dueDate);
      return;
    }

    final Money roundedAmount = enteredAmount.roundUpToWholePeso();
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => _ConfirmPostingDialog(
            consumerName: widget.entry.consumerName,
            enteredAmount: enteredAmount,
            roundedAmount: roundedAmount,
            dueDate: dueDate,
          ),
        ) ??
        false;

    if (!mounted || !confirmed) return;
    widget.onPost(_amount.text, dueDate);
  }
}

/// Looks like the amount box above it, opens the calendar.
class _DueDateField extends StatelessWidget {
  final PhDate? dueDate;
  final bool enabled;
  final VoidCallback onTap;

  const _DueDateField({
    required this.dueDate,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final PhDate? date = dueDate;

    return Semantics(
      button: true,
      label: 'Due date',
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            enabled: enabled,
            prefixIcon: const Icon(Icons.event_outlined),
            suffixIcon: const Icon(Icons.expand_more),
          ),
          child: Text(
            date == null ? 'Choose the date on the statement' : _longDate(date),
            style: date == null
                ? text.bodyLarge?.copyWith(color: colours.onSurfaceVariant)
                : text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _ConfirmPostingDialog extends StatelessWidget {
  final String consumerName;
  final Money enteredAmount;
  final Money roundedAmount;
  final PhDate dueDate;

  const _ConfirmPostingDialog({
    required this.consumerName,
    required this.enteredAmount,
    required this.roundedAmount,
    required this.dueDate,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool wasRounded = enteredAmount != roundedAmount;

    return AlertDialog(
      title: const Text('Confirm bill amount'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(consumerName, style: text.titleMedium),
          const SizedBox(height: 16),
          if (wasRounded) ...<Widget>[
            _ConfirmationRow(
              label: 'Amount entered',
              value: enteredAmount.format(),
            ),
            const SizedBox(height: 8),
          ],
          _ConfirmationRow(
            label: wasRounded ? 'Rounded amount to post' : 'Amount to post',
            value: roundedAmount.format(),
            valueStyle: text.titleLarge?.copyWith(
              color: colours.primary,
              fontFeatures: _tabularFigures,
            ),
          ),
          const SizedBox(height: 8),
          _ConfirmationRow(label: 'Due date', value: _longDate(dueDate)),
          const SizedBox(height: 16),
          Text(
            'Posting makes this bill payable and sends the consumer alert, '
            'in the app and by text. '
            'The amount cannot be changed in the app afterward.',
            style: text.bodySmall,
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Review'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Post amount'),
        ),
      ],
    );
  }
}

class _ConfirmationRow extends StatelessWidget {
  final String label;
  final String value;
  final TextStyle? valueStyle;

  const _ConfirmationRow({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: <Widget>[
      Expanded(child: Text(label)),
      const SizedBox(width: 12),
      Text(
        value,
        style:
            valueStyle ??
            Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontFeatures: _tabularFigures),
      ),
    ],
  );
}

/// "6 days", "today" — how long the household has waited for its figure.
class _WaitBadge extends StatelessWidget {
  final AwaitingAmountEntry entry;

  const _WaitBadge({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tone = _waitTone(context, entry.daysWaiting);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        entry.waitLabel,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(color: tone.foreground),
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
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'READING DETAIL',
                style: text.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${entry.bill.cycle.displayName} · ${entry.bill.billNo.value}',
                  style: text.bodySmall?.copyWith(
                    fontFeatures: _tabularFigures,
                  ),
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                  value: _shortDate(entry.readingDate),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Check the amount against this consumption — a wildly wrong '
            'figure stands out.',
            style: text.bodySmall,
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
        Text(
          value,
          style: (emphasise ? text.titleMedium : text.bodyLarge)?.copyWith(
            fontFeatures: _tabularFigures,
          ),
        ),
      ],
    );
  }
}
