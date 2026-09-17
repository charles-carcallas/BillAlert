import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/usecases/reader/load_reading_sheet.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/kwh.dart';
import '../../domain/value_objects/ph_date.dart';
import '../auth/auth_controller.dart';
import '../common/failure_banner.dart';
import '../providers.dart';

/// The sheet for [month] in the signed-in reader's area.
final readingSheetProvider = FutureProvider.autoDispose
    .family<ReadingSheet, CycleLabel>((Ref ref, CycleLabel month) async {
      final user = await ref.watch(authControllerProvider.future);
      final areaId = user?.areaId;
      if (areaId == null) {
        throw const PermissionFailure(
          'No service area is attached to this account, so there is no '
          'reading sheet to show.',
        );
      }
      final result = await ref.read(loadReadingSheetProvider)(
        areaId: areaId,
        cycle: month,
      );
      return switch (result) {
        Ok(:final value) => value,
        Err(:final failure) => throw failure,
      };
    });

/// Meter Reader › Readings › Reading sheet.
///
/// Step 2 of the reader's month used to be copying every reading out of a
/// notebook onto BOHECO's paper. This is that list, already written: every
/// household in the area in purok order, its previous and present reading
/// and the kWh between them, with the meters nobody has read yet left
/// visibly blank. "Copy for BOHECO" puts it on the clipboard as a table that
/// pastes into a spreadsheet, a message or a notes app to print.
class ReadingSheetScreen extends ConsumerStatefulWidget {
  const ReadingSheetScreen({super.key});

  @override
  ConsumerState<ReadingSheetScreen> createState() => _ReadingSheetScreenState();
}

class _ReadingSheetScreenState extends ConsumerState<ReadingSheetScreen> {
  CycleLabel? _month;
  bool _onlyNotRead = false;

  @override
  Widget build(BuildContext context) {
    final CycleLabel current = CycleLabel.of(
      ref.watch(phClockProvider).today(),
    );
    final CycleLabel month = _month ?? current;
    final AsyncValue<ReadingSheet> sheet = ref.watch(
      readingSheetProvider(month),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Reading sheet')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(readingSheetProvider(month).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _SummaryPanel(
                month: month,
                sheet: sheet.value,
                onPrevious: () => setState(() => _month = _shift(month, -1)),
                onNext: month == current
                    ? null
                    : () => setState(() => _month = _shift(month, 1)),
                onCopy: sheet.value == null
                    ? null
                    : () => _copy(context, sheet.value!),
              ),
              ...sheet.when(
                loading: () => const <Widget>[
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (Object error, StackTrace _) => <Widget>[
                  const SizedBox(height: 16),
                  FailureBanner(
                    failure: error is AppFailure
                        ? error
                        : ServerFailure(ServerFailure.defaultMessage, '$error'),
                    onRetry: () => ref.invalidate(readingSheetProvider(month)),
                  ),
                ],
                data: (ReadingSheet value) => _body(value),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(ReadingSheet sheet) {
    final List<(int, ReadingSheetRow)> numbered = <(int, ReadingSheetRow)>[
      for (int i = 0; i < sheet.rows.length; i++) (i + 1, sheet.rows[i]),
    ];
    final List<(int, ReadingSheetRow)> visible = _onlyNotRead
        ? numbered.where(((int, ReadingSheetRow) r) => !r.$2.isRead).toList()
        : numbered;

    return <Widget>[
      if (sheet.serverFailure != null) ...<Widget>[
        const SizedBox(height: 12),
        FailureBanner(
          failure: NetworkFailure(
            'Readings already sent to the server cannot be loaded without '
            'signal. Readings on this phone and unread meters are still '
            'listed.',
            sheet.serverFailure!.debugDetail,
          ),
          onRetry: () => ref.invalidate(readingSheetProvider(sheet.cycle)),
        ),
      ],
      const SizedBox(height: 16),
      Row(
        children: <Widget>[
          ChoiceChip(
            label: Text('All ${sheet.rows.length}'),
            selected: !_onlyNotRead,
            onSelected: (_) => setState(() => _onlyNotRead = false),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text('Not read ${sheet.notReadCount}'),
            selected: _onlyNotRead,
            onSelected: (_) => setState(() => _onlyNotRead = true),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (visible.isEmpty)
        _Empty(
          message: sheet.rows.isEmpty
              ? 'No households on this phone yet. Open the Readings tab with '
                    'signal to download them.'
              : 'Every meter in your area has been read.',
        )
      else
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < visible.length; i++) ...<Widget>[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 58,
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                _SheetRow(number: visible[i].$1, row: visible[i].$2),
              ],
            ],
          ),
        ),
    ];
  }

  static CycleLabel _shift(CycleLabel month, int by) {
    final int index = month.year * 12 + (month.month - 1) + by;
    return CycleLabel(index ~/ 12, index % 12 + 1);
  }

  Future<void> _copy(BuildContext context, ReadingSheet sheet) async {
    final String reader =
        ref.read(authControllerProvider).value?.fullName ?? '';
    await Clipboard.setData(
      ClipboardData(text: readingSheetText(sheet, reader: reader)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Reading sheet copied. Paste it into a spreadsheet, message or note.',
        ),
      ),
    );
  }
}

/// The sheet as tab-separated text: a heading, then one line per household.
/// Tabs make it land in columns when pasted into a spreadsheet, and still
/// read as a list in a plain message.
String readingSheetText(ReadingSheet sheet, {String reader = ''}) {
  final StringBuffer out = StringBuffer()
    ..writeln('Reading sheet — ${sheet.cycle.displayName}');
  if (reader.isNotEmpty) out.writeln('Meter reader: $reader');
  out
    ..writeln(
      'Read: ${sheet.readCount} of ${sheet.rows.length}   '
      'Total: ${sheet.totalConsumption.format()}',
    )
    ..writeln()
    ..writeln(
      <String>[
        'No.',
        'Account',
        'Name',
        'Purok',
        'Meter',
        'Previous',
        'Present',
        'kWh',
        'Date read',
      ].join('\t'),
    );
  for (int i = 0; i < sheet.rows.length; i++) {
    final ReadingSheetRow row = sheet.rows[i];
    out.writeln(
      <String>[
        '${i + 1}',
        row.household.consumerNo.value,
        row.household.fullName,
        row.household.purok ?? '',
        row.household.meterSerialNo ?? '',
        _bare(row.previousReading),
        row.state == SheetRowState.notRead
            ? 'NOT READ'
            : row.state == SheetRowState.recordedFiguresUnavailable
            ? 'READ (sync to load)'
            : _bare(row.currentReading),
        _bare(row.consumption),
        row.readingDate == null ? '' : _longDate(row.readingDate!),
      ].join('\t'),
    );
  }
  return out.toString();
}

/// "4,668.00" — a reading without its unit, for a table column.
String _bare(Kwh? reading) =>
    reading == null ? '' : reading.format().replaceFirst(' kWh', '');

class _SummaryPanel extends StatelessWidget {
  final CycleLabel month;
  final ReadingSheet? sheet;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCopy;

  const _SummaryPanel({
    required this.month,
    required this.sheet,
    required this.onPrevious,
    required this.onNext,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final ReadingSheet? value = sheet;
    final int total = value?.rows.length ?? 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.08),
        border: Border.all(color: colours.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconButton(
                tooltip: 'Previous month',
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  month.displayName,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(
                    color: colours.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    Text(
                      value == null ? '—' : '${value.readCount}',
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colours.primary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'of $total meters read',
                        style: text.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: value == null || total == 0
                        ? 0
                        : value.readCount / total,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _Stat(
                        label: 'Not read',
                        value: value == null ? '—' : '${value.notReadCount}',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _Stat(
                        label: 'Total consumption',
                        value: value == null
                            ? '—'
                            : value.totalConsumption.format(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: const Text('Copy for BOHECO'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: text.labelSmall?.copyWith(color: colours.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final int number;
  final ReadingSheetRow row;

  const _SheetRow({required this.number, required this.row});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final bool dark = colours.brightness == Brightness.dark;
    final Color amber = dark
        ? const Color(0xFFF2B866)
        : const Color(0xFF8A5100);
    final String identity = <String>[
      row.household.consumerNo.value,
      if (row.household.purok != null) row.household.purok!,
      if (row.household.meterSerialNo != null) row.household.meterSerialNo!,
    ].join(' · ');
    final bool hasFigures =
        row.state == SheetRowState.synced ||
        row.state == SheetRowState.waitingToSync;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (row.isRead ? colours.primary : amber).withValues(
                    alpha: 0.12,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$number',
                  style: text.labelMedium?.copyWith(
                    color: row.isRead ? colours.primary : amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      row.household.fullName,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      identity,
                      style: text.bodySmall?.copyWith(
                        color: colours.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (row.state == SheetRowState.notRead) ...<Widget>[
                const SizedBox(width: 8),
                _Tag(
                  icon: Icons.radio_button_unchecked,
                  label: 'Not read',
                  colour: amber,
                ),
              ],
              if (row.state ==
                  SheetRowState.recordedFiguresUnavailable) ...<Widget>[
                const SizedBox(width: 8),
                _Tag(
                  icon: Icons.check_circle_outline,
                  label: 'Read',
                  colour: colours.primary,
                ),
              ],
            ],
          ),
          if (hasFigures) ...<Widget>[
            const SizedBox(height: 10),
            // The figures copied onto BOHECO's paper, large enough to read
            // off the screen at arm's length without squinting.
            Padding(
              padding: const EdgeInsets.only(left: 46),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _Figure(
                      label: 'Previous',
                      value: _bare(row.previousReading),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _Figure(
                      label: 'Present',
                      value: _bare(row.currentReading),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _Figure(
                      label: 'kWh used',
                      value: _bare(row.consumption),
                      emphasised: true,
                    ),
                  ),
                ],
              ),
            ),
            if (row.state == SheetRowState.waitingToSync) ...<Widget>[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 46),
                child: _Tag(
                  icon: Icons.cloud_upload_outlined,
                  label: 'On this phone · waiting to sync',
                  colour: colours.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One labelled reading in a row's figures strip.
class _Figure extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasised;

  const _Figure({
    required this.label,
    required this.value,
    this.emphasised = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: emphasised
            ? colours.primary.withValues(alpha: 0.10)
            : colours.surfaceContainerHigh.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: text.labelSmall?.copyWith(color: colours.onSurfaceVariant),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value.isEmpty ? '—' : value,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: emphasised ? colours.primary : colours.onSurface,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color colour;

  const _Tag({required this.icon, required this.label, required this.colour});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(icon, size: 14, color: colour),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: colour,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}

class _Empty extends StatelessWidget {
  final String message;

  const _Empty({required this.message});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

const List<String> _monthsShort = <String>[
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

String _longDate(PhDate date) =>
    '${date.day} ${_monthsShort[date.month - 1]} ${date.year}';
