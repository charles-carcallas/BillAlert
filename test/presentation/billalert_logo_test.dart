import 'package:billalert/presentation/common/billalert_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('logo renders locally in $brightness theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(body: Center(child: BillAlertLogo())),
        ),
      );
      expect(tester.getSize(find.byType(BillAlertLogo)), const Size(64, 64));
      expect(find.bySemanticsLabel('BillAlert logo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
