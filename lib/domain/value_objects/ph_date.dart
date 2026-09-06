/// A calendar date in Asia/Manila.
///
/// Billing dates in BillAlert are Philippine calendar dates, decided by the
/// server with `fn_ph_today()`. The app must never use the device's local
/// time for them: a phone whose timezone is wrong — or a reader who crosses
/// midnight UTC while still in the same Philippine day — would otherwise file
/// a reading into the wrong billing cycle, or show a bill as overdue a day
/// early.
///
/// The Philippines is a fixed UTC+08:00 and has had no daylight saving since
/// 1978, so the offset is a constant and no timezone database is needed.
/// That is what keeps this class pure Dart.
final class PhDate implements Comparable<PhDate> {
  /// Philippine Standard Time. Fixed, no daylight saving.
  static const Duration utcOffset = Duration(hours: 8);

  final int year;
  final int month;
  final int day;

  const PhDate(this.year, this.month, this.day);

  /// The Philippine calendar date at [instant], whatever timezone the phone
  /// happens to be set to.
  factory PhDate.at(DateTime instant) {
    final manila = instant.toUtc().add(utcOffset);
    return PhDate(manila.year, manila.month, manila.day);
  }

  /// Parses "2026-09-13" as a `date` column returns it. Null when malformed.
  static PhDate? tryParse(String text) {
    final trimmed = text.trim();
    if (trimmed.length < 10) return null;
    final year = int.tryParse(trimmed.substring(0, 4));
    final month = int.tryParse(trimmed.substring(5, 7));
    final day = int.tryParse(trimmed.substring(8, 10));
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return PhDate(year, month, day);
  }

  /// "2026-09-13", the form a `date` column and PostgREST both expect.
  String toIso() {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }

  /// Midnight Manila on this date, as a UTC instant. Used only to compare
  /// and subtract dates, never to display a time.
  DateTime get _asUtcMidnight => DateTime.utc(year, month, day);

  bool isAfter(PhDate other) => _asUtcMidnight.isAfter(other._asUtcMidnight);

  bool isBefore(PhDate other) => _asUtcMidnight.isBefore(other._asUtcMidnight);

  /// Whole days from [other] to this date. Positive when this is later.
  int daysSince(PhDate other) =>
      _asUtcMidnight.difference(other._asUtcMidnight).inDays;

  @override
  bool operator ==(Object other) =>
      other is PhDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  int compareTo(PhDate other) =>
      _asUtcMidnight.compareTo(other._asUtcMidnight);

  @override
  String toString() => toIso();
}
