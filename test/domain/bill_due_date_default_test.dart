import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Bill bill(int year, int month) => Bill(
    id: const BillId('bill'),
    billNo: const BillNumber('TEST'),
    consumerId: const ConsumerId('house'),
    cycle: CycleLabel(year, month),
    consumption: Kwh.zero,
    totalAmount: null,
    dueDate: null,
  );
  test(
    '28th is the default before and on that day, requiring a choice afterward',
    () {
      final october = bill(2026, 10);
      expect(
        october.suggestedDueDate(const PhDate(2026, 10, 21)),
        const PhDate(2026, 10, 28),
      );
      expect(
        october.suggestedDueDate(const PhDate(2026, 10, 28)),
        const PhDate(2026, 10, 28),
      );
      expect(october.suggestedDueDate(const PhDate(2026, 10, 29)), isNull);
    },
  );
  test('saved due day clamps to the bill month and never rolls forward', () {
    expect(
      bill(2028, 2).suggestedDueDate(const PhDate(2028, 2, 1), defaultDay: 31),
      const PhDate(2028, 2, 29),
    );
    expect(
      bill(
        2026,
        10,
      ).suggestedDueDate(const PhDate(2026, 10, 21), defaultDay: 20),
      isNull,
    );
    expect(
      bill(
        2026,
        10,
      ).suggestedDueDate(const PhDate(2026, 10, 1), defaultDay: 25),
      const PhDate(2026, 10, 25),
    );
  });
  test('delayed September bill never acquires an October default', () {
    expect(bill(2026, 9).suggestedDueDate(const PhDate(2026, 10, 2)), isNull);
  });
  test('February and December/January retain the bill cycle', () {
    expect(
      bill(2028, 2).suggestedDueDate(const PhDate(2028, 2, 1)),
      const PhDate(2028, 2, 28),
    );
    expect(bill(2026, 12).suggestedDueDate(const PhDate(2027, 1, 1)), isNull);
    expect(
      bill(2027, 1).suggestedDueDate(const PhDate(2027, 1, 1)),
      const PhDate(2027, 1, 28),
    );
  });
  test(
    'Philippine midnight, not the UTC date, decides whether default passed',
    () {
      expect(
        bill(
          2026,
          10,
        ).suggestedDueDate(PhDate.at(DateTime.utc(2026, 10, 28, 16))),
        isNull,
      );
    },
  );
}
