import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/consumer/contact_number_controller.dart';
import 'package:billalert/presentation/consumer/edit_contact_number_sheet.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  const ConsumerUser consumer = ConsumerUser(
    id: ProfileId('consumer-profile-1'),
    username: 'virgilio.busalanan',
    firstName: 'Virgilio',
    lastName: 'Busalanan',
    mustChangePassword: false,
  );
  const CashierUser cashier = CashierUser(
    id: ProfileId('cashier-1'),
    username: 'mercedita.gales',
    firstName: 'Mercedita',
    lastName: 'Gales',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  test(
    'controller returns the server-normalized number for a consumer',
    () async {
      final consumers = FakeConsumerRepository(<Consumer>[])
        ..normalizedContactNumber = '+639175550999';
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: consumer),
          ),
          consumerRepositoryProvider.overrideWithValue(consumers),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(consumerContactNumberControllerProvider.notifier)
          .update('0917 555 0999');

      expect(
        container.read(consumerContactNumberControllerProvider).savedNumber,
        '+639175550999',
      );
      expect(consumers.updatedContactText, '0917 555 0999');
    },
  );

  test('controller refuses a staff account before repository access', () async {
    final consumers = FakeConsumerRepository(<Consumer>[]);
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
        .read(consumerContactNumberControllerProvider.notifier)
        .update('0917 555 0999');

    expect(consumers.updateContactCount, 0);
    expect(
      container.read(consumerContactNumberControllerProvider).failure,
      isA<PermissionFailure>(),
    );
  });

  testWidgets('the number is saved only after final confirmation', (
    WidgetTester tester,
  ) async {
    final consumers = FakeConsumerRepository(<Consumer>[])
      ..normalizedContactNumber = '+639175550999';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: consumer),
          ),
          consumerRepositoryProvider.overrideWithValue(consumers),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => TextButton(
                onPressed: () => showEditConsumerContactNumber(
                  context,
                  currentNumber: '+639175550142',
                ),
                child: const Text('Edit number'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Edit number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey<String>('consumer-contact-number')),
      '0917 555 0999',
    );
    await tester.tap(find.text('Review new number'));
    await tester.pumpAndSettle();

    expect(find.text('Update SMS number?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('0917 555 0999'),
      ),
      findsOneWidget,
    );
    expect(consumers.updateContactCount, 0);

    await tester.tap(find.text('Update number'));
    await tester.pumpAndSettle();

    expect(consumers.updateContactCount, 1);
    expect(consumers.updatedContactText, '0917 555 0999');
    expect(find.text('SMS delivery number'), findsNothing);
  });
}
