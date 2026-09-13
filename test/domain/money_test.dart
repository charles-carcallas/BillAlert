import 'package:billalert/domain/value_objects/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money is not a double', () {
    test('adding ten centavos ten times gives exactly one peso', () {
      // This is the whole argument for the class, in one test.
      var total = Money.zero;
      for (var i = 0; i < 10; i++) {
        total = total + Money.parse('0.10');
      }

      expect(total, Money.parse('1.00'));
      expect(total.centavos, 100);

      // The same sum written with doubles, which is what the class exists to
      // avoid. If this ever starts passing, Dart has changed how binary
      // floating point works and the comment above needs revisiting.
      var wrong = 0.0;
      for (var i = 0; i < 10; i++) {
        wrong += 0.10;
      }
      expect(
        wrong == 1.0,
        isFalse,
        reason: 'double addition of 0.10 ten times is not exactly 1.00',
      );
    });

    test('a cashier settling three months adds up exactly', () {
      final june = Money.parse('658.30');
      final july = Money.parse('1975.35');
      final august = Money.parse('2946.50');

      expect((june + july + august).format(), '₱5,580.15');
    });
  });

  group('arithmetic and comparison', () {
    test('subtraction gives the balance', () {
      final total = Money.parse('658.30');
      final paid = Money.parse('200.00');
      expect(total - paid, Money.parse('458.30'));
    });

    test('subtracting more than the total goes negative', () {
      expect((Money.parse('10.00') - Money.parse('25.50')).centavos, -1550);
    });

    test('comparison operators', () {
      expect(Money.parse('100.00') < Money.parse('100.01'), isTrue);
      expect(Money.parse('100.00') >= Money.parse('100.00'), isTrue);
      expect(Money.parse('99.99') > Money.parse('100.00'), isFalse);
    });

    test('two amounts with the same centavos are equal and hash alike', () {
      final a = Money.of(1975, 35);
      final b = Money.parse('1975.35');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(<Money>{a, b}.length, 1);
    });
  });

  group('whole-peso ceiling', () {
    test(
      'always rounds a centavo fraction up and leaves exact pesos alone',
      () {
        expect(Money.parse('499.01').roundUpToWholePeso(), Money.of(500));
        expect(Money.parse('499.99').roundUpToWholePeso(), Money.of(500));
        expect(Money.parse('499.00').roundUpToWholePeso(), Money.of(499));
      },
    );
  });

  group('parsing', () {
    test('accepts what a numeric(12,2) column returns', () {
      expect(Money.parse('1975.35').centavos, 197535);
      expect(Money.parse('0.00').centavos, 0);
    });

    test('accepts what a person types', () {
      expect(Money.parse('1,975.35').centavos, 197535);
      expect(Money.parse('658.3').centavos, 65830);
      expect(Money.parse('658').centavos, 65800);
      expect(Money.parse(' 658.30 ').centavos, 65830);
      expect(Money.parse('₱658.30').centavos, 65830);
    });

    test('refuses three decimals rather than rounding them away', () {
      // Silently turning 10.555 into 10.55 or 10.56 would be the app
      // inventing a peso amount, which it must never do.
      expect(Money.tryParse('10.555'), isNull);
    });

    test('refuses text that is not an amount', () {
      expect(Money.tryParse(''), isNull);
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.2.3'), isNull);
      expect(Money.tryParse('-'), isNull);
    });
  });

  group('formatting', () {
    test('groups thousands and always shows two decimals', () {
      expect(Money.parse('0').format(), '₱0.00');
      expect(Money.parse('5.5').format(), '₱5.50');
      expect(Money.parse('658.30').format(), '₱658.30');
      expect(Money.parse('1975.35').format(), '₱1,975.35');
      expect(Money.parse('1234567.89').format(), '₱1,234,567.89');
    });

    test('a negative amount keeps its sign in front', () {
      expect(const Money.fromCentavos(-65830).format(), '-₱658.30');
    });

    test('the database form has no sign, comma or symbol', () {
      expect(Money.parse('1,975.35').toDatabaseString(), '1975.35');
      expect(Money.parse('658.3').toDatabaseString(), '658.30');
      expect(Money.of(0, 5).toDatabaseString(), '0.05');
    });
  });
}
