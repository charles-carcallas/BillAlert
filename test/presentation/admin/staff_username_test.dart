import 'package:billalert/presentation/admin/new_staff_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('staff username follows names until manually changed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AdminNewStaffScreen())),
    );
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Rodrigo');
    await tester.enterText(fields.at(1), 'Balistoy');
    await tester.pump();
    String username() =>
        tester.widget<TextField>(fields.at(3)).controller!.text;
    expect(username(), 'rodrigo.balistoy');
    await tester.enterText(fields.at(0), 'Juan Carlos');
    expect(username(), 'juancarlos.balistoy');
    await tester.enterText(fields.at(3), 'juancarlos.balistoy2');
    await tester.enterText(fields.at(1), 'Santos');
    expect(username(), 'juancarlos.balistoy2');
    expect(tester.takeException(), isNull);
  });
}
