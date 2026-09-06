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

  /// Parses "2026-09". Null when malformed.
  static CycleLabel? tryParse(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 7) return null;
    final year = int.tryParse(trimmed.substring(0, 4));
    final month = int.tryParse(trimmed.substring(5, 7));
    if (year == null || month == null) return null;
    if (month < 1 || month > 12) return null;
    return CycleLabel(year, month);
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
