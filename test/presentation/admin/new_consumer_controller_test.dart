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

  test('controller supplies the signed-in Admin area and profile id', () async {
    final consumers = FakeConsumerRepository(<Consumer>[]);
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: admin),
        ),
        consumerRepositoryProvider.overrideWithValue(consumers),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(adminNewConsumerControllerProvider.notifier)
        .create(
          consumerNo: '2026-1234-TUB',
          firstName: 'Lorna',
          lastName: 'Caberte',
          contactNumber: '',
          purok: 'Purok 4',
        );

    expect(consumers.createdAreaId, area3);
    expect(consumers.createdBy, admin.id);
    expect(
      container.read(adminNewConsumerControllerProvider).created?.fullName,
      'Lorna Caberte',
    );
  });

  test('a non-Admin cannot create a household', () async {
    final consumers = FakeConsumerRepository(<Consumer>[]);
    const cashier = CashierUser(
      id: ProfileId('cashier-1'),
      username: 'cashier',
      firstName: 'Mercedita',
      lastName: 'Gales',
      areaId: area3,
      mustChangePassword: false,
    );
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: cashier),
        ),
        consumerRepositoryProvider.overrideWithValue(consumers),
      ],
    );
    addTearDown(container.dispose);

    await container
        .read(adminNewConsumerControllerProvider.notifier)
        .create(
          consumerNo: '2026-1234-TUB',
          firstName: 'Lorna',
          lastName: 'Caberte',
          contactNumber: '',
          purok: '',
        );

    expect(consumers.createCount, 0);
    expect(
      container.read(adminNewConsumerControllerProvider).failure,
      isA<PermissionFailure>(),
    );
  });

  testWidgets(
    'form includes required schema fields and excludes forbidden ones',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AdminNewConsumerScreen())),
      );

      expect(find.text('Consumer number'), findsOneWidget);
      expect(find.text('First name'), findsOneWidget);
      expect(find.text('Last name'), findsOneWidget);
      expect(find.text('Mobile number (optional)'), findsOneWidget);
      expect(find.text('Purok (optional)'), findsOneWidget);
      expect(find.text('Barangay'), findsNothing);
      expect(find.textContaining('Meter serial'), findsNothing);
      expect(find.textContaining('Staff account'), findsNothing);
      expect(find.textContaining('temporary password'), findsNothing);
    },
  );

  testWidgets('creation requires confirmation of the permanent record', (
    WidgetTester tester,
  ) async {
    final consumers = FakeConsumerRepository(<Consumer>[]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: admin),
          ),
          consumerRepositoryProvider.overrideWithValue(consumers),
        ],
        child: const MaterialApp(home: AdminNewConsumerScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final Finder fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '2026-1234-TUB');
    await tester.enterText(fields.at(1), 'Lorna');
    await tester.enterText(fields.at(2), 'Caberte');

    final Finder purok = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField && widget.decoration?.hintText == 'e.g. Purok 3',
    );
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.enterText(purok.first, 'Purok 4');

    final Finder create = find.text('Create consumer account');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(find.text('Confirm new consumer'), findsOneWidget);
    expect(find.text('Lorna Caberte'), findsOneWidget);
    expect(find.text('2026-1234-TUB'), findsWidgets);
    expect(consumers.createCount, 0);

    await tester.tap(find.text('Create consumer'));
    await tester.pumpAndSettle();
    expect(consumers.createCount, 1);
  });
}
