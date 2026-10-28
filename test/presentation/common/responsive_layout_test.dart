import 'package:billalert/presentation/common/responsive_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide cards use columns and compact cards use rows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ResponsiveCards(
            children: [
              SizedBox(key: ValueKey('one'), height: 200),
              SizedBox(key: ValueKey('two'), height: 200),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('one'))).dy,
      tester.getTopLeft(find.byKey(const ValueKey('two'))).dy,
    );
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('two'))).dy, 200);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sign-in remains usable in a short laptop window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 450);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopSignInLayout(
            child: SingleChildScrollView(
              child: SizedBox(width: 420, height: 650, child: Text('Sign in')),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Your community.\nYour bills, together.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
