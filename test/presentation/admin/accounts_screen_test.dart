import 'package:billalert/presentation/admin/accounts_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Accounts switches between staff and consumer creation forms', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AdminAccountsScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('New account'), findsOneWidget);
    expect(find.text('Staff account'), findsOneWidget);
    expect(find.text('Consumer account'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
    expect(find.text('Consumer number'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'Rodrigo');
    await tester.tap(find.text('Consumer account'));
    await tester.pumpAndSettle();

    expect(find.text('Consumer number'), findsOneWidget);
    expect(find.text('Role'), findsNothing);
    // MTR-04: a household added earlier gets its sign-in from here. It sits
    // below the form, so the lazily built list is scrolled to it first.
    final Finder giveSignIn = find.text('Give an existing household a sign-in');
    await tester.scrollUntilVisible(
      giveSignIn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(giveSignIn, findsOneWidget);

    await tester.tap(find.text('Staff account'));
    await tester.pumpAndSettle();

    expect(find.text('Rodrigo'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
  });
}
