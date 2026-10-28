import 'dart:async';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/repositories/notice_repository.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:billalert/presentation/admin/notice_document_controller.dart';
import 'package:billalert/presentation/admin/notice_document_screen.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/common/saved_list_time.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

class _Notices implements NoticeRepository {
  late NoticeReview value;
  int closes = 0;
  AppFailure? failure;
  Completer<Result<NoticeReview?>>? pendingReview;
  @override
  Future<Result<NoticeReview?>> review(NoticeId id) async =>
      pendingReview == null ? Ok(value) : await pendingReview!.future;
  @override
  Future<Result<void>> closeNotice({
    required NoticeId noticeId,
    required NoticeOutcome outcome,
    String? notes,
  }) async {
    closes++;
    return failure == null ? const Ok(null) : Err(failure!);
  }

  @override
  Future<Result<List<ActiveNotice>>> activeFor(AreaId areaId) async =>
      const Ok([]);
  @override
  Future<Result<List<ClosedNotice>>> historyFor(AreaId areaId) async =>
      const Ok([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NoticeReview _review({bool ready = false, String status = 'active'}) =>
    NoticeReview(
      notice: ActiveNotice(
        id: const NoticeId('notice'),
        noticeNo: 'DN-TEST',
        consumerId: const ConsumerId('house'),
        consumerLabel: 'Test household',
        servedAt: DateTime.utc(2026, 10, 2),
        earliestLawfulAt: DateTime.utc(2026, 10, 4),
        periodElapsed: false,
        amountOverdue: ready ? Money.zero : Money.parse('500'),
        hoursRemaining: 48,
        reason: 'Overdue bill',
        readyToClose: ready,
      ),
      status: status,
      checkedAt: DateTime.utc(2026, 10, 2),
      closedAt: status == 'active' ? null : DateTime.utc(2026, 10, 3),
      closedBy: status == 'active' ? null : 'Test Admin',
      outcomeNotes: status == 'active' ? null : 'Receipt checked',
      coveredBills: [
        NoticeBillItem(
          billNo: 'SEPTEMBER',
          cycle: 'September 2026',
          dueDate: '2026-09-28',
          balance: ready ? Money.zero : Money.parse('500'),
          amountAtIssue: Money.parse('500'),
        ),
      ],
      overdueBills: [],
      receipts: ready
          ? [
              NoticeReceipt(
                receiptNo: 'EXACT-RECEIPT',
                billNo: 'SEPTEMBER',
                amount: Money.parse('500'),
                paidAt: DateTime.utc(2026, 10, 2),
              ),
            ]
          : [],
      sms: [const NoticeSms(status: 'sent')],
    );

void main() {
  const admin = AdminUser(
    id: ProfileId('admin'),
    username: 'test',
    firstName: 'Test',
    lastName: 'Admin',
    areaId: AreaId('area'),
    mustChangePassword: false,
  );
  late _Notices repo;
  late ProviderContainer container;
  setUp(() {
    repo = _Notices()..value = _review();
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: admin),
        ),
        noticeRepositoryProvider.overrideWithValue(repo),
        savedListTimeProvider.overrideWith((ref, key) => Stream.value(null)),
      ],
    );
  });
  tearDown(() => container.dispose());
  Future<NoticeDocumentController> loaded() async {
    await container.read(authControllerProvider.future);
    final controller = container.read(
      noticeDocumentControllerProvider('notice').notifier,
    );
    await controller.load();
    return controller;
  }

  test('unpaid Settled is rejected before the server call', () async {
    final controller = await loaded();
    expect(await controller.close(outcome: NoticeOutcome.settled), isFalse);
    expect(repo.closes, 0);
    expect(
      container.read(noticeDocumentControllerProvider('notice')).failure,
      isA<ValidationFailure>(),
    );
  });
  test('cancellation and referral require supporting notes', () async {
    final controller = await loaded();
    for (final outcome in [NoticeOutcome.cancelled, NoticeOutcome.referred]) {
      expect(await controller.close(outcome: outcome, notes: '  '), isFalse);
    }
    expect(repo.closes, 0);
    expect(
      await controller.close(
        outcome: NoticeOutcome.cancelled,
        notes: 'Wrong service record',
      ),
      isTrue,
    );
    expect(repo.closes, 1);
  });
  test('stale ready state cannot claim a closure the server refused', () async {
    repo.value = _review(ready: true);
    repo.failure = const ValidationFailure('Another overdue balance remains');
    final controller = await loaded();
    expect(await controller.close(outcome: NoticeOutcome.settled), isFalse);
    expect(
      container.read(noticeDocumentControllerProvider('notice')).closedOutcome,
      isNull,
    );
    expect(repo.closes, 1);
  });
  test(
    'network loss reports uncertainty rather than claiming nothing was saved',
    () async {
      repo.value = _review(ready: true);
      repo.failure = const NetworkFailure();
      final controller = await loaded();
      expect(await controller.close(outcome: NoticeOutcome.settled), isFalse);
      expect(
        container
            .read(noticeDocumentControllerProvider('notice'))
            .failure!
            .message,
        contains('could not be confirmed'),
      );
    },
  );
  test('existing closed history cannot be closed again', () async {
    repo.value = _review(ready: true, status: 'settled');
    final controller = await loaded();
    expect(
      await controller.close(outcome: NoticeOutcome.cancelled, notes: 'Wrong'),
      isFalse,
    );
    expect(repo.closes, 0);
  });
  test('an older refresh cannot reopen a successfully closed notice', () async {
    repo.value = _review(ready: true);
    final controller = await loaded();
    repo.pendingReview = Completer<Result<NoticeReview?>>();
    final refresh = controller.load();
    expect(await controller.close(outcome: NoticeOutcome.settled), isTrue);
    repo.pendingReview!.complete(Ok(repo.value));
    await refresh;
    final state = container.read(noticeDocumentControllerProvider('notice'));
    expect(state.closedOutcome, NoticeOutcome.settled);
    expect(state.notice, isNull);
  });
  testWidgets(
    'review shows receipt and SMS evidence and disables unsupported Settled',
    (tester) async {
      await loaded();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: NoticeDocumentScreen(noticeId: 'notice'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bills covered by this notice'), findsOneWidget);
      expect(find.text('Notice SMS delivery'), findsOneWidget);
      expect(find.text('Sent by gateway'), findsOneWidget);
      final button = find.text('Close this notice');
      await tester.scrollUntilVisible(
        button,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(button);
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Settled'),
      );
      expect(chip.onSelected, isNull);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
