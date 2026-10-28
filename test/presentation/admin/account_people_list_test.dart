import 'package:billalert/data/repositories/account_management_repository.dart';
import 'package:billalert/presentation/admin/account_people_list.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final people = <AccountRow>[
    {
      'id': 'admin',
      'first_name': 'Mario',
      'last_name': 'Ombajin',
      'username': 'mario',
      'role': 'admin',
      'account_status': 'active',
      'staff_enabled': true,
    },
    {
      'id': 'reader',
      'first_name': 'Test',
      'last_name': 'Reader',
      'username': 'test.reader',
      'role': 'meter_reader',
      'account_status': 'active',
      'staff_enabled': true,
    },
  ];

  for (final width in [390.0, 1100.0]) {
    testWidgets(
      'person details retain household setup and access controls at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final actions = <String>[];
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: Scaffold(
                body: ListView(
                  children: [
                    AccountPeopleList(
                      people: people,
                      households: const [],
                      currentUserId: 'admin',
                      onAction: (person, action) =>
                          actions.add('${person['id']}:$action'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.text('Set up household'), findsNothing);
        expect(find.byIcon(Icons.swap_horiz), findsNothing);
        await tester.tap(find.text('Mario Ombajin (You)'));
        await tester.pumpAndSettle();
        expect(find.text('Set up my household'), findsOneWidget);
        expect(find.text('Disable login'), findsNothing);
        expect(find.text('Area President transfer'), findsNothing);
        await tester.tap(find.byTooltip('Close account details'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Test Reader'));
        await tester.pumpAndSettle();
        expect(find.text('@test.reader'), findsOneWidget);
        expect(find.text('Set up household'), findsOneWidget);
        expect(find.text('BOHECO coverage'), findsNothing);
        final action = find.text('End work access');
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(actions, ['reader:end_work']);
        expect(find.byTooltip('Close account details'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
