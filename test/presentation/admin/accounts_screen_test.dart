import 'dart:async';
import 'package:billalert/data/network/network_status.dart';
import 'package:billalert/data/repositories/account_management_repository.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/account_management_providers.dart';
import 'package:billalert/presentation/admin/create_account_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../support/fakes.dart';

class LinkedRepository extends AccountManagementRepository {
  LinkedRepository()
    : super(
        SupabaseClient(
          'https://example.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final requests = <AccountRow>[];
  bool reject = false;
  @override
  Future<AccountRow> workspace() async => {
    'people': [],
    'households': [
      {
        'id': 'h1',
        'consumer_no': 'EXIST-1',
        'first_name': 'Own',
        'last_name': 'Household',
        'account_status': 'active',
        'profile_id': null,
      },
      {
        'id': 'h2',
        'consumer_no': 'LINKED-1',
        'first_name': 'Someone',
        'last_name': 'Else',
        'account_status': 'active',
        'profile_id': 'other',
      },
    ],
    'transfers': [],
    'audit': [],
  };
  @override
  Future<String> createLinkedAccount(AccountRow body) async {
    requests.add(body);
    if (reject) {
      throw const AccountManagementException(
        'Consumer number is already in use.',
        safeToRetry: true,
      );
    }
    return 'created';
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    LinkedRepository repo, {
    double width = 390,
    double scale = 1,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final network = NetworkStatus(
      linkChanges: const Stream.empty(),
      checkLink: () async => true,
    );
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(
            signedInUser: const AdminUser(
              id: ProfileId('admin'),
              username: 'admin',
              firstName: 'Test',
              lastName: 'Admin',
              areaId: AreaId('area'),
              mustChangePassword: false,
            ),
          ),
        ),
        accountManagementRepositoryProvider.overrideWithValue(repo),
        temporaryPasswordFactoryProvider.overrideWithValue(
          () => 'test-only-password',
        ),
        networkStatusProvider.overrideWithValue(network),
      ],
    );
    addTearDown(() {
      container.dispose();
      network.dispose();
      unawaited(repo.client.dispose());
    });
    await container.read(authControllerProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? AppTheme.dark() : AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const AdminCreateAccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'New',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Last name'),
      'Person',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Consumer number'),
      'TEST-NEW',
    );
  }

  testWidgets(
    'one form requires household confirmation and creates one linked account',
    (tester) async {
      final repo = LinkedRepository();
      await mount(tester, repo);
      await fill(tester);
      await tap(tester, 'Create account');
      expect(repo.requests, isEmpty);
      await tap(tester, 'This is their own household');
      await tap(tester, 'Retry setup');
      expect(repo.requests, hasLength(1));
      expect(repo.requests.single['household']['consumer_no'], 'TEST-NEW');
      expect(repo.requests.single['username'], 'new.person');
      expect(find.text('Account and household ready'), findsOneWidget);
      expect(find.text('test-only-password'), findsOneWidget);
    },
  );
  testWidgets('existing household selection excludes already linked accounts', (
    tester,
  ) async {
    final repo = LinkedRepository();
    await mount(tester, repo);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'Own',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Last name'),
      'Person',
    );
    await tap(tester, 'Existing');
    await tap(tester, 'Unlinked household');
    expect(find.textContaining('LINKED-1'), findsNothing);
    await tap(tester, 'EXIST-1 · Own Household');
    await tap(tester, 'This is their own household');
    await tap(tester, 'Create account');
    expect(repo.requests.single['household']['id'], 'h1');
    expect(repo.requests.single['household']['mode'], 'existing');
  });
  testWidgets(
    'definite rejection permits corrected retry without another workflow',
    (tester) async {
      final repo = LinkedRepository()..reject = true;
      await mount(tester, repo);
      await fill(tester);
      await tap(tester, 'This is their own household');
      await tap(tester, 'Create account');
      expect(repo.requests, hasLength(1));
      repo.reject = false;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Consumer number'),
        'TEST-CORRECTED',
      );
      await tap(tester, 'Retry setup');
      expect(repo.requests, hasLength(2));
      expect(repo.requests.last['household']['consumer_no'], 'TEST-CORRECTED');
    },
  );
  for (final width in [320.0, 1100.0]) {
    testWidgets('linked form fits width $width with enlarged text', (
      tester,
    ) async {
      await mount(
        tester,
        LinkedRepository(),
        width: width,
        scale: 1.5,
        dark: width == 320,
      );
      await tap(tester, 'Create account');
      expect(tester.takeException(), isNull);
    });
  }
}
