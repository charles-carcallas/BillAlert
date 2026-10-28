import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/account_management_providers.dart';
import 'package:billalert/presentation/admin/account_management_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

void main() {
  for (final linked in [false, true]) {
    testWidgets('household login actions respect linked status: $linked', (
      tester,
    ) async {
      const admin = AdminUser(
        id: ProfileId('admin'),
        username: 'admin',
        firstName: 'Mario',
        lastName: 'Ombajin',
        areaId: AreaId('area'),
        mustChangePassword: false,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(
              () => FakeAuthController(signedInUser: admin),
            ),
            accountWorkspaceProvider.overrideWith(
              (ref) async => {
                'people': [
                  {
                    'id': 'admin',
                    'username': 'admin',
                    'first_name': 'Mario',
                    'last_name': 'Ombajin',
                    'role': 'admin',
                    'account_status': 'active',
                    'staff_enabled': true,
                  },
                ],
                'households': [
                  {
                    'id': 'household',
                    'consumer_no': 'TEST-1',
                    'first_name': 'Previous',
                    'last_name': 'Member',
                    'profile_id': linked ? 'admin' : null,
                    'account_status': 'active',
                  },
                ],
                'transfers': [],
                'audit': [],
              },
            ),
          ],
          child: const MaterialApp(home: AccountManagementScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create consumer login'), findsNothing);
      expect(find.text('Create replacement login'), findsNothing);
      await tester.tap(find.text('Households'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(
        find.text('Finish account setup'),
        linked ? findsNothing : findsOneWidget,
      );
      await tester.tap(find.text('Unrelated occupant handover'));
      await tester.pumpAndSettle();
      expect(find.text('Use existing login'), findsOneWidget);
      // A new occupant opens the unified household/account flow; credentials
      // are generated rather than entered in the old standalone dialog.
      expect(find.text('Create replacement login'), findsOneWidget);
    });
  }
}
