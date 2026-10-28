import 'dart:async';

import 'package:billalert/data/network/network_status.dart';
import 'package:billalert/data/repositories/account_management_repository.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/account_management_providers.dart';
import 'package:billalert/presentation/admin/account_management_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';

AccountRow person(
  String id,
  String name,
  String role, {
  bool enabled = true,
  String area = 'area',
  String status = 'active',
}) => {
  'id': id,
  'first_name': name,
  'last_name': 'Person',
  'username': id,
  'role': role,
  'staff_enabled': enabled,
  'area_id': area,
  'account_status': status,
  'access_version': 4,
};

class AssignmentRepository extends AccountManagementRepository {
  AssignmentRepository()
    : super(
        SupabaseClient(
          'https://example.invalid',
          'test-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final people = [
    person('admin', 'Mario', 'admin'),
    person('reader', 'Current reader', 'meter_reader'),
    person('cashier', 'Current cashier', 'cashier'),
    person('candidate', 'Available', 'consumer'),
    person('former', 'Former staff', 'meter_reader', enabled: false),
    person('inactive', 'Inactive', 'consumer', status: 'inactive'),
    person('other', 'Other area', 'consumer', area: 'other'),
  ];
  final missingLinks = <String>{};
  int assignments = 0, creations = 0;
  bool loseResponse = false, failCreation = false;
  Completer<void>? waiting;
  AccountRow? request;
  @override
  Future<AccountRow> workspace() async => {
    'people': people.map((p) => {...p}).toList(),
    'households': [
      for (final id in [
        'admin',
        'reader',
        'cashier',
        'candidate',
        'former',
        'new',
      ])
        if (!missingLinks.contains(id))
          {'profile_id': id, 'account_status': 'active'},
    ],
    'transfers': [],
    'audit': [],
  };
  @override
  Future<void> assignStaff({
    required String operation,
    required String role,
    required AccountRow replacement,
    required AccountRow? outgoing,
    required bool reconciled,
  }) async {
    assignments++;
    request = {
      'replacement': replacement['id'],
      'outgoing': outgoing?['id'],
      'replacement_version': replacement['access_version'],
      'reconciled': reconciled,
    };
    await waiting?.future;
    for (final p in people) {
      if (p['id'] == outgoing?['id']) p['staff_enabled'] = false;
      if (p['id'] == replacement['id']) {
        p['role'] = role;
        p['staff_enabled'] = true;
      }
    }
    if (loseResponse) {
      throw const AccountManagementException(
        AccountManagementRepository.uncertain,
      );
    }
  }

  @override
  Future<String> createLinkedAccount(AccountRow body) async {
    final firstName = body['first_name'] as String;
    final lastName = body['last_name'] as String;
    final username = body['username'] as String;
    creations++;
    if (failCreation) {
      throw const AccountManagementException(
        AccountManagementRepository.uncertain,
      );
    }
    people.add({
      ...person('new', firstName, 'consumer', enabled: false),
      'last_name': lastName,
      'username': username,
    });
    return 'new';
  }
}

void main() {
  Finder button(String label) => find
      .ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((widget) => widget is FilledButton),
      )
      .first;
  const admin = AdminUser(
    id: ProfileId('admin'),
    username: 'admin',
    firstName: 'Mario',
    lastName: 'Person',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );

  Future<NetworkStatus> mount(
    WidgetTester tester,
    AssignmentRepository repository, {
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
          () => FakeAuthController(signedInUser: admin),
        ),
        accountManagementRepositoryProvider.overrideWithValue(repository),
        networkStatusProvider.overrideWithValue(network),
        temporaryPasswordFactoryProvider.overrideWithValue(
          () => 'test-only-password',
        ),
      ],
    );
    addTearDown(
      () => tester.runAsync(() async {
        container.dispose();
        network.dispose();
        unawaited(repository.client.dispose());
      }),
    );
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
          home: const AccountManagementScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return network;
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final target = find.text(text);
    if (target.evaluate().isEmpty) await tester.scrollUntilVisible(target, 180);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) => tap(tester, 'Change Meter Reader');
  Future<void> fill(WidgetTester tester) async {
    await tap(tester, 'Add new person');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'First name'),
      'New',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Last name'),
      'Member',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Consumer number'),
      'TEST-NEW',
    );
    await tap(tester, 'This is their own household');
    await tap(tester, 'Create account');
  }

  testWidgets('missing outgoing household blocks replacement until resolved', (
    tester,
  ) async {
    final repository = AssignmentRepository()..missingLinks.add('reader');
    await mount(tester, repository);
    await open(tester);
    await tap(tester, 'Available Person');
    await tap(tester, 'Ready for handover');
    await tester.scrollUntilVisible(find.text('Confirm assignment'), 160);
    expect(
      tester.widget<FilledButton>(button('Confirm assignment')).onPressed,
      isNull,
    );
    expect(repository.assignments, 0);
    expect(find.text('Disable outgoing login'), findsOneWidget);
  });

  testWidgets('choose existing login and confirm one atomic replacement', (
    tester,
  ) async {
    final repository = AssignmentRepository();
    await mount(tester, repository);
    expect(find.text('Your staff'), findsOneWidget);
    await open(tester);
    expect(find.text('Available Person'), findsOneWidget);
    expect(find.text('Former staff Person'), findsOneWidget);
    expect(find.text('Other area Person'), findsNothing);
    expect(find.text('Inactive Person'), findsNothing);
    expect(find.text('Current cashier Person'), findsNothing);
    await tap(tester, 'Available Person');
    await tester.scrollUntilVisible(find.text('Confirm assignment'), 160);
    expect(
      tester.widget<FilledButton>(button('Confirm assignment')).onPressed,
      isNull,
    );
    expect(repository.assignments, 0);
    await tap(tester, 'Ready for handover');
    await tap(tester, 'Confirm assignment');
    expect(repository.assignments, 1);
    expect(repository.creations, 0);
    expect(repository.request, {
      'replacement': 'candidate',
      'outgoing': 'reader',
      'replacement_version': 4,
      'reconciled': true,
    });
    expect(find.text('Meter Reader assignment saved.'), findsOneWidget);
  });

  testWidgets('back from review changes nothing', (tester) async {
    final repository = AssignmentRepository();
    await mount(tester, repository);
    await open(tester);
    await tap(tester, 'Available Person');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(repository.assignments, 0);
    expect(repository.creations, 0);
  });

  testWidgets(
    'add person generates credentials but waits for handover confirmation',
    (tester) async {
      final repository = AssignmentRepository();
      await mount(tester, repository);
      await open(tester);
      await fill(tester);
      expect(repository.creations, 1);
      expect(repository.assignments, 0);
      expect(find.text('new.member'), findsOneWidget);
      expect(find.text('test-only-password'), findsOneWidget);
      await tap(tester, 'Continue to review');
      expect(find.text('New Member'), findsOneWidget);
      await tap(tester, 'Ready for handover');
      await tap(tester, 'Confirm assignment');
      expect(repository.assignments, 1);
      expect(repository.request!['replacement'], 'new');
    },
  );

  testWidgets('uncertain creation cannot be blindly submitted again', (
    tester,
  ) async {
    final repository = AssignmentRepository()..failCreation = true;
    await mount(tester, repository);
    await open(tester);
    await fill(tester);
    expect(repository.creations, 1);
    expect(
      tester.widget<FilledButton>(button('Retry setup')).onPressed,
      isNull,
    );
    await tap(tester, 'Back to check accounts');
    expect(repository.assignments, 0);
  });

  testWidgets(
    'lost assignment response requires refresh, never a second automatic write',
    (tester) async {
      final repository = AssignmentRepository()..loseResponse = true;
      await mount(tester, repository);
      await open(tester);
      await tap(tester, 'Available Person');
      await tap(tester, 'Ready for handover');
      await tap(tester, 'Confirm assignment');
      expect(repository.assignments, 1);
      await tester.scrollUntilVisible(find.text('Confirm assignment'), 180);
      expect(
        tester.widget<FilledButton>(button('Confirm assignment')).onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(find.text('Refresh accounts'), -200);
      await tap(tester, 'Refresh accounts');
      expect(
        find.text('Available Person'),
        findsOneWidget,
      ); // now the current holder
      expect(
        find.text('Current reader Person'),
        findsOneWidget,
      ); // now eligible
      expect(repository.assignments, 1);
    },
  );

  testWidgets('offline confirmation makes no write and keeps current staff', (
    tester,
  ) async {
    final repository = AssignmentRepository();
    final network = await mount(tester, repository);
    await open(tester);
    await tap(tester, 'Available Person');
    await tap(tester, 'Ready for handover');
    network.reportUnreachable();
    await tap(tester, 'Confirm assignment');
    expect(repository.assignments, 0);
    expect(
      find.textContaining('Staff changes need a connection.'),
      findsOneWidget,
    );
  });

  for (final layout in [(320.0, 1.5, true), (1100.0, 1.0, false)]) {
    testWidgets('staff picker and review fit $layout', (tester) async {
      final repository = AssignmentRepository();
      await mount(
        tester,
        repository,
        width: layout.$1,
        scale: layout.$2,
        dark: layout.$3,
      );
      expect(tester.takeException(), isNull);
      await open(tester);
      expect(tester.takeException(), isNull);
      await tap(tester, 'Available Person');
      await tap(tester, 'Ready for handover');
      expect(tester.takeException(), isNull);
    });
  }
}
