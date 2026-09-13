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

    await tester.tap(find.text('Staff account'));
    await tester.pumpAndSettle();

    expect(find.text('Rodrigo'), findsOneWidget);
    expect(find.text('Role'), findsOneWidget);
  });
}
