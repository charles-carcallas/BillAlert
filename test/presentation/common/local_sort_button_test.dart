import 'package:billalert/presentation/common/local_sort_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows current sort and returns a new choice', (tester) async {
    LocalNameSort current = LocalNameSort.az;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: LocalSortButton<LocalNameSort>(
              value: current,
              options: localNameSortOptions,
              onChanged: (value) => setState(() => current = value),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Name A–Z'), findsOneWidget);
    await tester.tap(find.text('Name A–Z'));
    await tester.pumpAndSettle();
    expect(find.text('Sort by'), findsOneWidget);
    await tester.tap(find.text('Name Z–A'));
    await tester.pumpAndSettle();

    expect(current, LocalNameSort.za);
    expect(find.text('Name Z–A'), findsOneWidget);
  });

  test('name comparison is case-insensitive in both directions', () {
    final names = <String>['zoe', 'Ana', 'ben'];
    names.sort((a, b) => compareNames(a, b, LocalNameSort.az));
    expect(names, <String>['Ana', 'ben', 'zoe']);
    names.sort((a, b) => compareNames(a, b, LocalNameSort.za));
    expect(names, <String>['zoe', 'ben', 'Ana']);
  });
}
