import 'package:billalert/data/network/network_status.dart';
import 'package:billalert/data/repositories/billing_schedule_repository.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/billing_schedule.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/presentation/admin/billing_schedule_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/fakes.dart';

class Schedules implements BillingScheduleRepository {
  BillingSchedule current = const BillingSchedule(
    version: 'v1',
    effectiveMonth: '2026-10-01',
  );
  BillingSchedule? submitted;
  String? scope;
  int saves = 0;
  @override
  Future<BillingSchedule> load(String scope) async => current;
  @override
  Future<BillingSchedule> save(
    BillingSchedule value,
    String id, {
    required String scope,
  }) async {
    saves++;
    submitted = value;
    this.scope = scope;
    return current = BillingSchedule(
      dueDay: value.dueDay,
      cutoffDay: value.cutoffDay,
      cutoffMinutes: value.cutoffMinutes,
      version: 'v2',
      effectiveMonth: '2026-11-01',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const admin = AdminUser(
    id: ProfileId('admin'),
    username: 'admin',
    firstName: 'Test',
    lastName: 'Admin',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  const cashier = CashierUser(
    id: ProfileId('cashier'),
    username: 'cashier',
    firstName: 'Test',
    lastName: 'Cashier',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  late Schedules repository;
  late NetworkStatus network;
  setUp(() {
    repository = Schedules();
    network = NetworkStatus(
      linkChanges: const Stream.empty(),
      checkLink: () async => true,
    );
  });
  tearDown(() => network.dispose());
  Future<void> open(WidgetTester tester, AppUser user) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            () => FakeAuthController(signedInUser: user),
          ),
          billingScheduleRepositoryProvider.overrideWithValue(repository),
          networkStatusProvider.overrideWithValue(network),
          clientUuidFactoryProvider.overrideWithValue(
            CountingUuidFactory().call,
          ),
        ],
        child: const MaterialApp(home: BillingScheduleScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('phone form saves due day and cutoff together with version', (
    tester,
  ) async {
    await open(tester, admin);
    expect(find.text('Monthly due day'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.text('Cashier collection closes'), findsNothing);
    expect(find.text('Timezone · Philippine time (UTC+8)'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day 25').last);
    await tester.pumpAndSettle();
    final save = find.text('Save schedule');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.saves, 1);
    expect(repository.submitted!.dueDay, 25);
    expect(repository.submitted!.cutoffDay, 25);
    expect(repository.submitted!.cutoffMinutes, 720);
    expect(repository.submitted!.version, 'v1');
    expect(repository.scope, admin.accessScope);
    expect(find.textContaining('Schedule saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('offline save remains local and makes no request', (
    tester,
  ) async {
    await open(tester, admin);
    network.reportUnreachable();
    await tester.pump();
    final save = find.text('Save schedule');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.saves, 0);
    expect(find.text('Connect to save the billing schedule.'), findsOneWidget);
  });
  testWidgets('cashier cannot open admin editor', (tester) async {
    await open(tester, cashier);
    expect(find.text('Area President access required.'), findsOneWidget);
    expect(find.text('Save schedule'), findsNothing);
  });
  testWidgets('reload adopts a newer version before another save', (
    tester,
  ) async {
    await open(tester, admin);
    repository.current = const BillingSchedule(
      dueDay: 23,
      version: 'v3',
      effectiveMonth: '2026-11-01',
    );
    final reload = find.byTooltip('Reload saved schedule');
    await tester.ensureVisible(reload);
    await tester.tap(reload);
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('Day 23'), findsOneWidget);
    final save = find.text('Save schedule');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(repository.submitted!.version, 'v3');
    expect(repository.submitted!.dueDay, 23);
    expect(repository.submitted!.cutoffDay, 23);
  });
}
