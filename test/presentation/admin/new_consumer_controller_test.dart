import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/new_consumer_controller.dart';
import 'package:billalert/presentation/admin/new_consumer_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  const AreaId area3 = AreaId('area-3');
  const AdminUser admin = AdminUser(
    id: ProfileId('admin-1'),
    username: 'mario.ombajin',
    firstName: 'Mario',
    lastName: 'Ombajin',
    areaId: area3,
    mustChangePassword: false,
  );

  late FakeConsumerRepository consumers;
  late FakeAuthRepository auth;

  setUp(() {
    consumers = FakeConsumerRepository(<Consumer>[]);
    auth = FakeAuthRepository();
  });

  ProviderContainer containerFor(AppUser user) {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: user),
        ),
        consumerRepositoryProvider.overrideWithValue(consumers),
        authRepositoryProvider.overrideWithValue(auth),
        temporaryPasswordFactoryProvider.overrideWithValue(
          () => 'BillAlert0042',
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> openForm(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: admin),
          ),
          consumerRepositoryProvider.overrideWithValue(consumers),
          authRepositoryProvider.overrideWithValue(auth),
          temporaryPasswordFactoryProvider.overrideWithValue(
            () => 'BillAlert0042',
          ),
        ],
        child: const MaterialApp(home: AdminNewConsumerScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder fieldWithHint(String hint) => find.byWidgetPredicate(
    (Widget widget) =>
        widget is TextField && widget.decoration?.hintText == hint,
  );

  /// The form is a lazily built list, so a field or button further down is
  /// scrolled to before it is used.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Fills the household, lets the username suggest itself, and taps Create.
  Future<void> fillAndSubmit(WidgetTester tester) async {
    final Finder fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '2026-1234-TUB');
    await tester.enterText(fields.at(1), 'Lorna');
    await tester.enterText(fields.at(2), 'Caberte');

    await scrollTo(tester, fieldWithHint('e.g. BIEC-08317'));
    await tester.enterText(
      fieldWithHint('e.g. BIEC-08317').first,
      'BIEC-08399',
    );

    final Finder create = find.text('Create consumer account');
    await scrollTo(tester, create);
    await tester.tap(create);
    await tester.pumpAndSettle();
  }

  test('controller registers the household and its sign-in', () async {
    final container = containerFor(admin);

    await container
        .read(adminNewConsumerControllerProvider.notifier)
        .create(
          consumerNo: '2026-1234-TUB',
          firstName: 'Lorna',
          lastName: 'Caberte',
          contactNumber: '',
          purok: 'Purok 4',
          meterSerialNo: 'BIEC-08399',
          username: 'lorna.caberte',
        );

    expect(consumers.createdAreaId, area3);
    expect(consumers.createdBy, admin.id);
    expect(consumers.createdMeterSerialNo, 'BIEC-08399');
    expect(auth.createdLoginUsername, 'lorna.caberte');

    final registered = container
        .read(adminNewConsumerControllerProvider)
        .registered;
    expect(registered?.household.fullName, 'Lorna Caberte');
    expect(registered?.login?.temporaryPassword, 'BillAlert0042');
  });

  test('a non-Admin cannot create a household or a sign-in', () async {
    const cashier = CashierUser(
      id: ProfileId('cashier-1'),
      username: 'cashier',
      firstName: 'Mercedita',
      lastName: 'Gales',
      areaId: area3,
      mustChangePassword: false,
    );
    final container = containerFor(cashier);

    await container
        .read(adminNewConsumerControllerProvider.notifier)
        .create(
          consumerNo: '2026-1234-TUB',
          firstName: 'Lorna',
          lastName: 'Caberte',
          contactNumber: '',
          purok: '',
          meterSerialNo: '',
          username: 'lorna.caberte',
        );

    expect(consumers.createCount, 0);
    expect(auth.createLoginCalls, 0);
    expect(
      container.read(adminNewConsumerControllerProvider).failure,
      isA<PermissionFailure>(),
    );
  });

  testWidgets('form asks for the household and its username', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AdminNewConsumerScreen())),
    );

    expect(find.text('Consumer number'), findsOneWidget);
    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Last name'), findsOneWidget);
    expect(find.text('Mobile number (optional)'), findsOneWidget);
    expect(find.text('Purok (optional)'), findsOneWidget);
    expect(find.text('Barangay'), findsNothing);
    expect(find.textContaining('Staff account'), findsNothing);

    await scrollTo(tester, find.text('Meter number (optional)'));
    expect(find.text('Meter number (optional)'), findsOneWidget);

    await scrollTo(tester, find.text('Username'));
    expect(find.text('Username'), findsOneWidget);
    // Nobody types the temporary password.
    expect(find.text('Temporary password'), findsOneWidget);
  });

  testWidgets('the username is suggested from the name as it is typed', (
    WidgetTester tester,
  ) async {
    await openForm(tester);

    await tester.enterText(find.byType(TextField).at(1), 'Lorna');
    await tester.enterText(find.byType(TextField).at(2), 'Caberte');
    await scrollTo(tester, fieldWithHint('e.g. lorna.caberte'));

    expect(find.text('lorna.caberte'), findsOneWidget);
  });

  testWidgets('creating a consumer shows its username and password once', (
    WidgetTester tester,
  ) async {
    await openForm(tester);
    await fillAndSubmit(tester);

    expect(find.text('Confirm new consumer'), findsOneWidget);
    expect(find.text('Lorna Caberte'), findsOneWidget);
    final Finder dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('BIEC-08399')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('lorna.caberte')),
      findsOneWidget,
    );
    expect(consumers.createCount, 0);
    expect(auth.createLoginCalls, 0);

    await tester.tap(find.text('Create consumer'));
    await tester.pumpAndSettle();

    expect(consumers.createCount, 1);
    expect(consumers.createdMeterSerialNo, 'BIEC-08399');
    expect(auth.createLoginCalls, 1);
    expect(auth.createdLoginUsername, 'lorna.caberte');
    expect(find.text('lorna.caberte'), findsOneWidget);
    expect(find.text('BillAlert0042'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Create the sign-in'), findsNothing);
  });

  testWidgets('a refused sign-in keeps the household and offers to finish it', (
    WidgetTester tester,
  ) async {
    auth.nextCreateLoginFailure = const ConflictFailure(
      'Username lorna.caberte is already taken.',
    );
    await openForm(tester);
    await fillAndSubmit(tester);
    await tester.tap(find.text('Create consumer'));
    await tester.pumpAndSettle();

    expect(consumers.createCount, 1);
    expect(
      find.text('Username lorna.caberte is already taken.'),
      findsOneWidget,
    );
    expect(find.textContaining('household is saved'), findsOneWidget);
    expect(find.text('Create the sign-in'), findsOneWidget);
    expect(find.text('BillAlert0042'), findsNothing);
  });
}
