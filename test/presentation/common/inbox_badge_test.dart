import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/presentation/common/role_shell.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Inbox badge updates and disappears when all alerts are read', (
    tester,
  ) async {
    Future<void> showCount(int count, {bool dark = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          home: Scaffold(
            body: RoleTab(
              tab: const AppTab(
                label: 'Inbox',
                route: '/consumer/inbox',
                icon: NavIcon.inbox,
              ),
              selected: false,
              unreadCount: count,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await showCount(3);
    expect(find.text('3'), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).alignment, Alignment.topRight);
    await showCount(2, dark: true);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsNothing);
    await showCount(0);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
    expect(find.text('0'), findsNothing);
    expect(find.text('Inbox'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
