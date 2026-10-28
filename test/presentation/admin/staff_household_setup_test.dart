import 'package:billalert/data/repositories/account_management_repository.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/consumer.dart' as domain;
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/account_management_providers.dart';
import 'package:billalert/presentation/admin/staff_household_setup.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/fakes.dart';

class SetupRepository extends AccountManagementRepository {
  SetupRepository()
    : super(
        SupabaseClient(
          'https://example.invalid',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  List<AccountRow> households = [];
  final links = <String>[];
  bool rejectLink = false;
  @override
  Future<AccountRow> workspace() async => {'households': households};
  @override
  Future<void> link(
    String consumer,
    String profile,
    String kind,
    String reference,
  ) async {
    links.add('$consumer:$profile:$kind');
    if (rejectLink) throw Exception('lost response');
  }
}

void main() {
  const admin = AdminUser(
    id: ProfileId('mario'),
    username: 'mario',
    firstName: 'Mario',
    lastName: 'Ombajin',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  Future<void> mount(
    WidgetTester tester,
    SetupRepository repository,
    FakeConsumerRepository consumers,
  ) => tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: admin),
        ),
        accountManagementRepositoryProvider.overrideWithValue(repository),
        consumerRepositoryProvider.overrideWithValue(consumers),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: StaffHouseholdSetupButton(
            person: {
              'id': 'mario',
              'first_name': 'Mario',
              'last_name': 'Ombajin',
            },
          ),
        ),
      ),
    ),
  );

  testWidgets('search excludes occupied households and confirms fixed owner', (
    tester,
  ) async {
    final repository = SetupRepository()
      ..households = [
        {
          'id': 'own',
          'consumer_no': 'A-1',
          'first_name': 'Mario',
          'last_name': 'Ombajin',
          'account_status': 'active',
          'profile_id': null,
        },
        {
          'id': 'other',
          'consumer_no': 'B-1',
          'first_name': 'Someone',
          'last_name': 'Else',
          'account_status': 'active',
          'profile_id': 'someone',
        },
      ];
    addTearDown(() {
      repository.client.dispose();
    });
    await mount(
      tester,
      repository,
      FakeConsumerRepository(<domain.Consumer>[]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up household'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose existing'));
    await tester.pumpAndSettle();
    expect(find.text('Someone Else'), findsNothing);
    await tester.enterText(find.byType(TextField), 'A-1');
    await tester.pump();
    await tester.tap(find.text('Mario Ombajin'));
    await tester.pumpAndSettle();
    expect(repository.links, isEmpty);
    await tester.tap(find.text('Link household'));
    await tester.pumpAndSettle();
    expect(repository.links, ['own:mario:staff_link']);
  });
  testWidgets('create prefills names and links without a second login', (
    tester,
  ) async {
    final repository = SetupRepository();
    addTearDown(() {
      repository.client.dispose();
    });
    final consumers = FakeConsumerRepository(<domain.Consumer>[]);
    await mount(tester, repository, consumers);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set up household'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create new'));
    await tester.pumpAndSettle();
    expect(find.text('Mario'), findsOneWidget);
    expect(find.text('Ombajin'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'NEW-1');
    await tester.tap(find.text('Create and link'));
    await tester.pumpAndSettle();
    expect(consumers.createCount, 1);
    expect(repository.links, ['created-consumer:mario:staff_link']);
  });
  testWidgets(
    'uncertain link keeps created household and never retries creation',
    (tester) async {
      final repository = SetupRepository()..rejectLink = true;
      addTearDown(() {
        repository.client.dispose();
      });
      final consumers = FakeConsumerRepository(<domain.Consumer>[]);
      await mount(tester, repository, consumers);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set up household'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'NEW-1');
      await tester.tap(find.text('Create and link'));
      await tester.pumpAndSettle();
      expect(consumers.createCount, 1);
      expect(repository.links.length, 1);
      expect(find.textContaining('do not create it again'), findsOneWidget);
    },
  );
}
