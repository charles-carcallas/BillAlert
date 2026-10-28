import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/common/staff_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cashier = CashierUser(
    id: ProfileId('cashier'),
    username: 'cashier',
    firstName: 'Test',
    lastName: 'Cashier',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  const reader = MeterReaderUser(
    id: ProfileId('reader'),
    username: 'reader',
    firstName: 'Test',
    lastName: 'Reader',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  test('trip notifications open the recipient role remittance screen', () {
    expect(staffDestinationAllowed(cashier, '/cashier/remit'), isTrue);
    expect(staffDestinationAllowed(reader, '/reader/remittance'), isTrue);
    expect(staffDestinationAllowed(cashier, '/reader/remittance'), isFalse);
    expect(staffDestinationAllowed(reader, '/cashier/remit'), isFalse);
    expect(staffDestinationAllowed(reader, '/admin/overdue'), isFalse);
    expect(staffDestinationAllowed(reader, 'https://example.com'), isFalse);
  });
}
