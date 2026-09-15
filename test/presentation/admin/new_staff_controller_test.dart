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

  Finder fieldWithHint(String hint) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is TextField && widget.decoration?.hintText == hint,
  );

  /// Fills the staff form and taps Create, which opens the confirmation.
  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.enterText(fieldWithHint('Given name'), 'Rodrigo');
    await tester.enterText(fieldWithHint('Surname'), 'Balistoy');

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.enterText(
      fieldWithHint('e.g. rodrigo.balistoy').first,
      'rodrigo.balistoy',
    );

    // The form is a lazily built list: the button below the username is not
    // built until the list is scrolled towards it.
    final Finder create = find.text('Create staff account');
    await tester.scrollUntilVisible(
      create,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();
  }

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
        );

    expect(auth.createStaffCalls, 1);
    expect(auth.createdStaffRole, StaffRole.cashier);
    // The real generator, not a typed password.
    expect(auth.createdStaffPassword, matches(RegExp(r'^BillAlert\d{4}$')));
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
    // Nobody types the temporary password any more; the form says so.
    expect(find.text('Temporary password'), findsOneWidget);
    expect(find.text('Confirm temporary password'), findsNothing);
    expect(find.textContaining('sent to this mobile number'), findsNothing);
  });

  testWidgets(
    'the temporary password appears only after the account is created',
    (WidgetTester tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => FakeAuthController(signedInUser: admin),
            ),
            authRepositoryProvider.overrideWithValue(auth),
            temporaryPasswordFactoryProvider.overrideWithValue(
              () => 'BillAlert0042',
            ),
          ],
          child: const MaterialApp(home: AdminNewStaffScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await fillAndSubmit(tester);

      expect(find.text('Confirm new staff account'), findsOneWidget);
      expect(find.text('Rodrigo Balistoy'), findsOneWidget);
      expect(find.text('rodrigo.balistoy'), findsWidgets);
      // Not in the confirmation: it does not exist until the account does.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('BillAlert0042'),
        ),
        findsNothing,
      );
      expect(auth.createStaffCalls, 0);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Create staff account'),
        ),
      );
      await tester.pumpAndSettle();

      expect(auth.createStaffCalls, 1);
      expect(auth.createdStaffPassword, 'BillAlert0042');
      expect(find.text('BillAlert0042'), findsOneWidget);
      expect(find.text('rodrigo.balistoy'), findsOneWidget);
    },
  );

  testWidgets('choosing "Review" in the confirmation creates nothing', (
    WidgetTester tester,
  ) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: admin),
          ),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(home: AdminNewStaffScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await fillAndSubmit(tester);
    expect(find.text('Confirm new staff account'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(auth.createStaffCalls, 0);
  });
}
