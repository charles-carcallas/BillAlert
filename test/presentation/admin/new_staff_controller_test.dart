import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/staff_account.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/new_staff_controller.dart';
import 'package:billalert/presentation/admin/new_staff_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  const admin = AdminUser(
    id: ProfileId('admin-1'),
    username: 'mario.ombajin',
    firstName: 'Mario',
    lastName: 'Ombajin',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  test('controller lets the signed-in Area President create staff', () async {
    final auth = FakeAuthRepository();
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: admin),
        ),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(adminNewStaffControllerProvider.notifier)
        .create(
          username: 'rodrigo.balistoy',
          firstName: 'Rodrigo',
          lastName: 'Balistoy',
          contactNumber: '',
          role: StaffRole.cashier,
          temporaryPassword: 'Temporary#42',
          confirmPassword: 'Temporary#42',
        );

    expect(auth.createStaffCalls, 1);
    expect(auth.createdStaffRole, StaffRole.cashier);
    expect(
      container.read(adminNewStaffControllerProvider).created?.fullName,
      'Rodrigo Balistoy',
    );
  });

  test('controller refuses a non-Admin before provisioning', () async {
    final auth = FakeAuthRepository();
    const cashier = CashierUser(
      id: ProfileId('cashier-1'),
      username: 'cashier',
      firstName: 'Mercedita',
      lastName: 'Gales',
      areaId: AreaId('area-3'),
      mustChangePassword: false,
    );
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: cashier),
        ),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(adminNewStaffControllerProvider.notifier)
        .create(
          username: 'rodrigo.balistoy',
          firstName: 'Rodrigo',
          lastName: 'Balistoy',
          contactNumber: '',
          role: StaffRole.meterReader,
          temporaryPassword: 'Temporary#42',
          confirmPassword: 'Temporary#42',
        );

    expect(auth.createStaffCalls, 0);
    expect(
      container.read(adminNewStaffControllerProvider).failure,
      isA<PermissionFailure>(),
    );
  });

  testWidgets('form exposes only the two staff roles the server permits', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AdminNewStaffScreen())),
    );

    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Last name'), findsOneWidget);
    expect(find.text('Meter Reader'), findsOneWidget);
    expect(find.text('Cashier'), findsOneWidget);
    expect(find.text('Admin'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -650));
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Temporary password'), findsOneWidget);
    expect(find.textContaining('sent to this mobile number'), findsNothing);
  });
}
