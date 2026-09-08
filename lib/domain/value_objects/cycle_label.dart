import 'ph_date.dart';

/// A billing cycle identified by its Philippine year and month, "2026-09".
///
/// This is the key FR-23 is checked against on the device: a consumer may be
/// read once per cycle, and the reader must be told at the meter rather than
/// an hour later at sync.
///
/// It is computed in Dart from a [PhDate] and passed into SQLite as a bound
/// value. The local schema's `strftime('%Y-%m','now','localtime')` is
/// deliberately not used: that reads the phone's clock and timezone, which
/// can disagree with the server's Philippine date and would put a reading in
/// the wrong cycle.
final class CycleLabel implements Comparable<CycleLabel> {
  final int year;
  final int month;

  const CycleLabel(this.year, this.month);

  /// The cycle a reading taken on [date] belongs to.
  factory CycleLabel.of(PhDate date) => CycleLabel(date.year, date.month);

  /// Parses either form a cycle label arrives in.
  ///
  /// Two forms exist because two different systems write it. The phone writes
  /// "2026-09" into `outbox_reading_keys` and `cached_consumers`. Supabase
  /// writes "September 2026", because `cycle_label` in every view is
  /// `to_char(period_start, 'FMMonth YYYY')`.
  ///
  /// Accepting both here, rather than in two methods, is deliberate: a caller
  /// holding a `cycle_label` should not have to know which of the two systems
  /// produced the string it is holding. Before this accepted the second form,
  /// every bill read from a view fell through to a fallback and displayed as
  /// January 1970.
  ///
  /// Returns null when the text is neither form.
  static CycleLabel? tryParse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return _tryParseIso(trimmed) ?? _tryParseMonthName(trimmed);
  }

  /// "2026-09", the form the device writes.
  static CycleLabel? _tryParseIso(String text) {
    if (text.length < 7) return null;
    final year = int.tryParse(text.substring(0, 4));
    final month = int.tryParse(text.substring(5, 7));
    if (year == null || month == null) return null;
    if (month < 1 || month > 12) return null;
    return CycleLabel(year, month);
  }

  /// "September 2026", the form the Supabase views return.
  static CycleLabel? _tryParseMonthName(String text) {
    final parts = text.split(' ');
    if (parts.length != 2) return null;

    final month = _monthNames.indexWhere(
      (String name) => name.toLowerCase() == parts[0].toLowerCase(),
    );
    if (month < 0) return null;

    final year = int.tryParse(parts[1]);
    if (year == null) return null;

    // indexWhere is zero-based; months are not.
    return CycleLabel(year, month + 1);
  }

  /// The cycle a view row belongs to, taking the most reliable form the row
  /// offers.
  ///
  /// The order matters, and it is the whole reason this method exists:
  ///
  /// 1. `cycle_year` and `cycle_month` — integers the server already computed.
  ///    Nothing to parse, nothing to misread.
  /// 2. `period_start` — an ISO date. Also unambiguous, and every view that
  ///    lacks the two integers still carries this one.
  /// 3. `cycle_label` — the rendered text, "September 2026". Last, because
  ///    reading a month back out of a formatted string is guesswork compared
  ///    with reading an integer. `v_readings_awaiting_amount` offers nothing
  ///    else, so the fallback is still needed.
  ///
  /// Returns null when the row carries none of the three, which means the
  /// view cannot say which cycle its own bill belongs to. That is a real
  /// error and the caller should treat it as one rather than substitute a
  /// date nobody chose.
  static CycleLabel? fromRow(Map<String, dynamic> row) {
    final Object? year = row['cycle_year'];
    final Object? month = row['cycle_month'];
    if (year is num && month is num) {
      final int monthValue = month.toInt();
      if (monthValue >= 1 && monthValue <= 12) {
        return CycleLabel(year.toInt(), monthValue);
      }
    }

    final Object? periodStart = row['period_start'];
    if (periodStart != null) {
      final PhDate? start = PhDate.tryParse(periodStart.toString());
      if (start != null) return CycleLabel.of(start);
    }

    final Object? label = row['cycle_label'];
    if (label != null) return tryParse(label.toString());

    return null;
  }

  /// "2026-09" — what goes in `cached_consumers.last_read_cycle` and
  /// `outbox_reading_keys.cycle_label`.
  String get value => '$year-${month.toString().padLeft(2, '0')}';

  static const List<String> _monthNames = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// "September 2026", for a screen.
  String get displayName => '${_monthNames[month - 1]} $year';

  @override
  bool operator ==(Object other) =>
      other is CycleLabel && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  int compareTo(CycleLabel other) {
    final byYear = year.compareTo(other.year);
    return byYear != 0 ? byYear : month.compareTo(other.month);
  }

  @override
  String toString() => value;
}
