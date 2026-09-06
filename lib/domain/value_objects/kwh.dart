/// A meter reading, or a consumption figure, in kilowatt-hours.
///
/// Held as a whole number of hundredths, matching the `numeric(12,2)` columns
/// on `meter_readings`. Same reasoning as `Money`: a reading is compared and
/// subtracted, and floating point makes both unreliable.
///
/// Subtraction is allowed here and nowhere else in the domain. Consumption is
/// `current - previous`, which is energy, not money. BillAlert derives kWh;
/// the cooperative derives pesos.
final class Kwh implements Comparable<Kwh> {
  /// The reading in hundredths of a kWh. 1234.50 kWh is 123450.
  final int hundredths;

  const Kwh.fromHundredths(this.hundredths);

  static const Kwh zero = Kwh.fromHundredths(0);

  factory Kwh.of(int whole, [int hundredths = 0]) =>
      Kwh.fromHundredths(whole * 100 + hundredths);

  /// Parses what the meter reader typed, or what the column returned.
  /// Returns null when the text is not a reading.
  static Kwh? tryParse(String text) {
    var s = text.trim().replaceAll(',', '').replaceAll(' ', '');
    if (s.isEmpty) return null;
    // A meter never runs backwards, so a negative reading is always a typo.
    if (s.startsWith('-')) return null;
    if (s.startsWith('+')) s = s.substring(1);

    final parts = s.split('.');
    if (parts.length > 2) return null;
    final wholeText = parts[0].isEmpty ? '0' : parts[0];
    final fractionText = parts.length == 2 ? parts[1] : '';
    if (fractionText.length > 2) return null;
    if (!_isAllDigits(wholeText)) return null;
    if (fractionText.isNotEmpty && !_isAllDigits(fractionText)) return null;

    final whole = int.tryParse(wholeText);
    final fraction = int.tryParse(fractionText.padRight(2, '0'));
    if (whole == null || fraction == null) return null;
    return Kwh.fromHundredths(whole * 100 + fraction);
  }

  factory Kwh.parse(String text) {
    final parsed = tryParse(text);
    if (parsed == null) {
      throw FormatException('Not a meter reading', text);
    }
    return parsed;
  }

  /// Consumption. The one subtraction the domain performs.
  Kwh operator -(Kwh other) => Kwh.fromHundredths(hundredths - other.hundredths);

  bool operator <(Kwh other) => hundredths < other.hundredths;
  bool operator <=(Kwh other) => hundredths <= other.hundredths;
  bool operator >(Kwh other) => hundredths > other.hundredths;
  bool operator >=(Kwh other) => hundredths >= other.hundredths;

  /// "1,234.50 kWh"
  String format() {
    final fraction = (hundredths % 100).toString().padLeft(2, '0');
    return '${_group(hundredths ~/ 100)}.$fraction kWh';
  }

  /// "1234.50", for an RPC argument.
  String toDatabaseString() {
    final fraction = (hundredths % 100).toString().padLeft(2, '0');
    return '${hundredths ~/ 100}.$fraction';
  }

  static bool _isAllDigits(String text) {
    if (text.isEmpty) return false;
    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) return false;
    }
    return true;
  }

  static String _group(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) => other is Kwh && other.hundredths == hundredths;

  @override
  int get hashCode => hundredths.hashCode;

  @override
  int compareTo(Kwh other) => hundredths.compareTo(other.hundredths);

  @override
  String toString() => format();
}
