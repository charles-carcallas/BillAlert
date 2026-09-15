import 'dart:math';

import 'package:billalert/domain/value_objects/temporary_password.dart';
import 'package:flutter_test/flutter_test.dart';

/// The temporary password an Area President hands over.
void main() {
  test('is BillAlert followed by exactly four digits', () {
    for (var i = 0; i < 500; i++) {
      expect(
        TemporaryPassword.generate(),
        matches(RegExp(r'^BillAlert\d{4}$')),
      );
    }
  });

  test('keeps the leading zeros, so it is always four digits', () {
    expect(TemporaryPassword.generate(const _Always(7)), 'BillAlert0007');
    expect(TemporaryPassword.generate(const _Always(9999)), 'BillAlert9999');
  });

  test('is not the same for everyone', () {
    final Set<String> seen = <String>{
      for (var i = 0; i < 50; i++) TemporaryPassword.generate(),
    };
    // Fifty draws from 10,000 all landing on one value would mean the
    // digits are not random at all.
    expect(seen.length, greaterThan(1));
  });

  test('is long enough for the server, which refuses under 8 characters', () {
    expect(TemporaryPassword.generate().length, greaterThanOrEqualTo(8));
  });
}

/// A "random" source that always answers [value].
final class _Always implements Random {
  final int value;

  const _Always(this.value);

  @override
  int nextInt(int max) => value;

  @override
  double nextDouble() => 0;

  @override
  bool nextBool() => false;
}
