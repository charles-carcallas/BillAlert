/// A peso amount, held as a whole number of centavos.
///
/// Money is never a `double` in this app. Binary floating point cannot
/// represent 0.10 exactly, so adding ten of them gives 0.9999999999999999
/// and not 1.00. BillAlert adds peso amounts together — a cashier settling
/// three months on one receipt — so a `double` here is a correctness bug,
/// not a style preference. There is a test for exactly this case.
///
/// Note what is missing: no multiplication and no division. The app never
/// derives a bill amount. The cooperative sends the peso figure and the
/// Admin types it in. Anything that multiplies its way to pesos has
/// misunderstood the domain.
final class Money implements Comparable<Money> {
  /// The amount in centavos. 1975.35 pesos is 197535.
  final int centavos;

  const Money.fromCentavos(this.centavos);

  static const Money zero = Money.fromCentavos(0);

  /// `Money.of(1975, 35)` is 1,975.35 pesos.
  factory Money.of(int pesos, [int centavos = 0]) =>
      Money.fromCentavos(pesos * 100 + centavos);

  /// Parses the decimal text a `numeric(12,2)` column returns ("1975.35"),
  /// or what a user typed ("1975.3", "1,975").
  ///
  /// Returns null when the text is not an amount, so the caller can raise a
  /// ValidationFailure in its own words rather than catch something.
  /// Deliberately goes through the string, never through `double.parse`.
  static Money? tryParse(String text) {
    var s = text.trim();
    // Strip the peso sign (U+20B1), a plain "P", grouping commas and spaces.
    s = s.replaceAll('₱', '');
    s = s.replaceAll('P', '').replaceAll('p', '');
    s = s.replaceAll(',', '').replaceAll(' ', '');
    if (s.isEmpty) return null;

    var isNegative = false;
    if (s.startsWith('-')) {
      isNegative = true;
      s = s.substring(1);
    } else if (s.startsWith('+')) {
      s = s.substring(1);
    }
    if (s.isEmpty) return null;

    final parts = s.split('.');
    if (parts.length > 2) return null;

    final wholeText = parts[0].isEmpty ? '0' : parts[0];
    final fractionText = parts.length == 2 ? parts[1] : '';
    // More than two decimals is not a peso amount. Refuse rather than round.
    if (fractionText.length > 2) return null;
    if (!_isAllDigits(wholeText)) return null;
    if (fractionText.isNotEmpty && !_isAllDigits(fractionText)) return null;

    final whole = int.tryParse(wholeText);
    final fraction = int.tryParse(fractionText.padRight(2, '0'));
    if (whole == null || fraction == null) return null;

    final total = whole * 100 + fraction;
    return Money.fromCentavos(isNegative ? -total : total);
  }

  /// Like [tryParse], but throws on bad input. For tests and constants.
  factory Money.parse(String text) {
    final parsed = tryParse(text);
    if (parsed == null) {
      throw FormatException('Not a peso amount', text);
    }
    return parsed;
  }

  Money operator +(Money other) =>
      Money.fromCentavos(centavos + other.centavos);

  Money operator -(Money other) =>
      Money.fromCentavos(centavos - other.centavos);

  /// Applies BillAlert's whole-peso billing rule.
  ///
  /// An exact peso stays unchanged; any centavo fraction moves to the next
  /// peso. This is a ceiling operation, not ordinary nearest-peso rounding:
  /// ₱499.01 and ₱499.99 both become ₱500.00.
  Money roundUpToWholePeso() {
    final int remainder = centavos % 100;
    if (remainder == 0) return this;
    return Money.fromCentavos(centavos + (100 - remainder));
  }

  bool operator <(Money other) => centavos < other.centavos;
  bool operator <=(Money other) => centavos <= other.centavos;
  bool operator >(Money other) => centavos > other.centavos;
  bool operator >=(Money other) => centavos >= other.centavos;

  bool get isZero => centavos == 0;
  bool get isNegative => centavos < 0;

  /// For the screen: "P1,975.35" with the peso sign.
  ///
  /// The digit grouping is written by hand on purpose. `package:intl` would
  /// do it, but importing it would give `domain/` a package dependency, and
  /// the dependency rule says the domain layer imports nothing.
  String format() {
    final sign = centavos < 0 ? '-' : '';
    final absolute = centavos.abs();
    final pesos = _group(absolute ~/ 100);
    final cents = (absolute % 100).toString().padLeft(2, '0');
    return '$sign₱$pesos.$cents';
  }

  /// For an RPC argument: "1975.35". Always two decimals, never a `double`.
  String toDatabaseString() {
    final sign = centavos < 0 ? '-' : '';
    final absolute = centavos.abs();
    final cents = (absolute % 100).toString().padLeft(2, '0');
    return '$sign${absolute ~/ 100}.$cents';
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
  bool operator ==(Object other) =>
      other is Money && other.centavos == centavos;

  @override
  int get hashCode => centavos.hashCode;

  @override
  int compareTo(Money other) => centavos.compareTo(other.centavos);

  @override
  String toString() => format();
}
