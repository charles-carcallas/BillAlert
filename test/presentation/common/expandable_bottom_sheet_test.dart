import 'package:billalert/presentation/common/expandable_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester, {bool dismissible = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showExpandableBottomSheet<void>(
                  context: context,
                  initialSize: 0.5,
                  dismissible: dismissible,
                  builder: (_, ScrollController controller) => ListView(
                    controller: controller,
                    children: <Widget>[
                      for (int i = 0; i < 40; i++)
                        ListTile(title: Text('Row $i')),
                    ],
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  double sheetHeight(WidgetTester tester) =>
      tester.getSize(find.byType(ListView)).height;

  testWidgets('laptop opens a centered scrollable dialog', (tester) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.getSize(find.byType(ListView)).width, 760);
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop draft cannot be dismissed by clicking outside', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester, dismissible: false);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the grip up makes the sheet full screen', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final double half = sheetHeight(tester);

    await tester.drag(
      find.bySemanticsLabel('Drag to resize'),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(sheetHeight(tester), greaterThan(half * 1.6));
  });

  testWidgets('dragging the list up grows the sheet before scrolling', (
    WidgetTester tester,
  ) async {
    await open(tester);
    final double half = sheetHeight(tester);

    await tester.drag(find.text('Row 1'), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(sheetHeight(tester), greaterThan(half * 1.6));
  });

  testWidgets('a non-dismissible sheet resizes but never closes on drag', (
    WidgetTester tester,
  ) async {
    await open(tester, dismissible: false);

    await tester.drag(
      find.bySemanticsLabel('Drag to resize'),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('dragging a dismissible sheet down closes it', (
    WidgetTester tester,
  ) async {
    await open(tester);

    await tester.drag(
      find.bySemanticsLabel('Drag to resize'),
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
  });
}
