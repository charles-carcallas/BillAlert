import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/household_login.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/household_login_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// MTR-04: an Area President giving a household a sign-in.
void main() {
  const AdminUser admin = AdminUser(
    id: ProfileId('admin-1'),
    username: 'mario.ombajin',
    firstName: 'Mario',
    lastName: 'Ombajin',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  const HouseholdWithoutLogin lorna = HouseholdWithoutLogin(
    id: ConsumerId('consumer-lorna'),
    consumerNo: ConsumerNumber('2026-1204-TUB'),
    firstName: 'Lorna',
    lastName: 'Caberte',
    purok: 'Purok 3',
  );

  const HouseholdWithoutLogin odelon = HouseholdWithoutLogin(
    id: ConsumerId('consumer-odelon'),
    consumerNo: ConsumerNumber('2022-1287-TUB'),
    firstName: 'Odelon',
    lastName: 'Paredes',
  );

  late FakeAuthRepository auth;

  setUp(() {
    auth = FakeAuthRepository()
      ..withoutLogin = <HouseholdWithoutLogin>[lorna, odelon];
  });

  Future<void> open(
    WidgetTester tester, {
    AppUser signedIn = admin,
    HouseholdWithoutLogin? household,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: signedIn),
          ),
          authRepositoryProvider.overrideWithValue(auth),
          temporaryPasswordFactoryProvider.overrideWithValue(
            () => 'BillAlert0042',
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: AdminHouseholdLoginScreen(household: household),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    // The form is a lazily built list, so it is scrolled to the button
    // rather than assuming the button has been built.
    final Finder button = find.widgetWithText(FilledButton, 'Create sign-in');
    await tester.scrollUntilVisible(
      button,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> confirmDialog(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Create sign-in'),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists households without a sign-in, and search narrows it', (
    WidgetTester tester,
  ) async {
    await open(tester);

    expect(find.text('Lorna Caberte'), findsOneWidget);
    expect(find.text('2026-1204-TUB · Purok 3'), findsOneWidget);
    expect(find.text('Odelon Paredes'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '2022-1287');
    await tester.pumpAndSettle();

    expect(find.text('Odelon Paredes'), findsOneWidget);
    expect(find.text('Lorna Caberte'), findsNothing);
  });

  testWidgets('an area where every household can sign in says so', (
    WidgetTester tester,
  ) async {
    auth.withoutLogin = <HouseholdWithoutLogin>[];
    await open(tester);

    expect(find.text('Every household can sign in'), findsOneWidget);
  });

  testWidgets(
    'choosing a household suggests a username, and asks no password',
    (WidgetTester tester) async {
      await open(tester);

      await tester.tap(find.text('Lorna Caberte'));
      await tester.pumpAndSettle();

      expect(find.text('Create a sign-in'), findsOneWidget);
      expect(find.text('lorna.caberte'), findsOneWidget);
      // The username is the only thing typed.
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets('a confirmed sign-in shows its username and password once', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Lorna Caberte'));
    await tester.pumpAndSettle();

    await submit(tester);

    // The final confirmation, because this opens the household's data to
    // whoever holds the password.
    expect(find.text('Create this sign-in?'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('BillAlert0042'),
      ),
      findsNothing,
    );
    expect(auth.createLoginCalls, 0);

    await confirmDialog(tester);

    expect(auth.createLoginCalls, 1);
    expect(auth.createdLoginHousehold?.id.value, 'consumer-lorna');
    expect(auth.createdLoginUsername, 'lorna.caberte');
    expect(auth.createdLoginPassword, 'BillAlert0042');
    expect(find.text('Sign-in created for Lorna Caberte'), findsOneWidget);
    expect(find.text('lorna.caberte'), findsOneWidget);
    expect(find.text('BillAlert0042'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Give another household a sign-in'), findsOneWidget);
  });

  testWidgets('choosing "Review" in the confirmation creates nothing', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Lorna Caberte'));
    await tester.pumpAndSettle();

    await submit(tester);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(auth.createLoginCalls, 0);
    expect(find.text('Create a sign-in'), findsOneWidget);
  });

  testWidgets('a malformed username is refused before any confirmation', (
    WidgetTester tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('Lorna Caberte'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '2026lorna');
    await submit(tester);

    expect(find.text('Create this sign-in?'), findsNothing);
    expect(find.textContaining('must start with a letter'), findsOneWidget);
    expect(auth.createLoginCalls, 0);
  });

  testWidgets("the server's refusal is shown, and the form stays", (
    WidgetTester tester,
  ) async {
    auth.nextCreateLoginFailure = const ConflictFailure(
      'Username lorna.caberte is already taken.',
    );
    await open(tester);
    await tester.tap(find.text('Lorna Caberte'));
    await tester.pumpAndSettle();

    await submit(tester);
    await confirmDialog(tester);

    expect(
      find.text('Username lorna.caberte is already taken.'),
      findsOneWidget,
    );
    expect(find.text('Create a sign-in'), findsOneWidget);
    expect(find.text('BillAlert0042'), findsNothing);
  });

  testWidgets(
    'opened for a household just created, it goes straight to the form',
    (WidgetTester tester) async {
      await open(tester, household: lorna);

      expect(find.text('Create a sign-in'), findsOneWidget);
      expect(find.text('lorna.caberte'), findsOneWidget);
      expect(find.text('Odelon Paredes'), findsNothing);

      await submit(tester);
      await confirmDialog(tester);

      // There is no list to return to, so no "another" either.
      expect(find.text('Sign-in created for Lorna Caberte'), findsOneWidget);
      expect(find.text('BillAlert0042'), findsOneWidget);
      expect(find.text('Give another household a sign-in'), findsNothing);
    },
  );

  testWidgets('anyone but an Area President is told why, not shown a list', (
    WidgetTester tester,
  ) async {
    await open(
      tester,
      signedIn: const MeterReaderUser(
        id: ProfileId('reader-1'),
        username: 'ledesman.dormal',
        firstName: 'Ledesman',
        lastName: 'Dormal',
        areaId: AreaId('area-3'),
        mustChangePassword: false,
      ),
    );

    expect(
      find.text(
        'Only an Area President can give a household in their service area '
        'a sign-in.',
      ),
      findsOneWidget,
    );
    expect(find.text('Lorna Caberte'), findsNothing);
  });
}
