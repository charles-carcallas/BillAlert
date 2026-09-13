import 'dart:async';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/sync/sync_service.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/entities/staff_account.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/repositories/auth_repository.dart';
import 'package:billalert/domain/repositories/bill_repository.dart';
import 'package:billalert/domain/repositories/consumer_repository.dart';
import 'package:billalert/domain/repositories/outbox_repository.dart';
import 'package:billalert/domain/repositories/reading_repository.dart';
import 'package:billalert/domain/time/ph_clock.dart';
import 'package:billalert/domain/value_objects/cycle_label.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/kwh.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';

/// Hand-written stand-ins for the real repositories.
///
/// These exist to prove a claim about the architecture: a use case can be
/// tested with no Supabase, no SQLite, no Flutter binding and no network,
/// because it depends on interfaces declared in `domain/` rather than on any
/// of those things. If a use case ever stops being testable this way, the
/// dependency rule has been broken somewhere.

/// A clock stopped at a date the test chooses. Without this, "has this
/// household been read this cycle?" would answer differently in September
/// than in October, and the test would start failing on the first of a month
/// for no reason anyone could find.
final class FixedPhClock implements PhClock {
  final DateTime _instant;

  const FixedPhClock(this._instant);

  /// Noon in Manila on the given date, which is safely inside the day
  /// whichever way the offset is applied.
  factory FixedPhClock.onPhDate(PhDate date) =>
      FixedPhClock(DateTime.utc(date.year, date.month, date.day, 4));

  @override
  DateTime nowUtc() => _instant.toUtc();

  @override
  PhDate today() => PhDate.at(_instant);
}

/// An outbox that remembers what it was given, in a list.
final class FakeOutboxRepository implements OutboxRepository {
  final List<OutboxOperation> enqueued = <OutboxOperation>[];

  /// Set this to make the next enqueue fail, for testing the unhappy path.
  AppFailure? failNextWith;

  @override
  Future<Result<void>> enqueue(OutboxOperation operation) async {
    final failure = failNextWith;
    if (failure != null) {
      failNextWith = null;
      return Err<void>(failure);
    }
    enqueued.add(operation);
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<OutboxEntry>>> pending() async => Ok<List<OutboxEntry>>(
    enqueued
        .map(
          (OutboxOperation op) => OutboxEntry(
            operation: op,
            status: OutboxStatus.pending,
            attempts: 0,
            createdAt: op.capturedAt,
          ),
        )
        .toList(),
  );

  @override
  Future<Result<List<OutboxEntry>>> all() => pending();

  @override
  Future<Result<void>> markSyncing(ClientUuid clientUuid) async =>
      const Ok<void>(null);

  @override
  Future<Result<void>> markSynced(
    ClientUuid clientUuid,
    String serverId,
  ) async => const Ok<void>(null);

  @override
  Future<Result<void>> markFailed(ClientUuid clientUuid, String reason) async =>
      const Ok<void>(null);

  @override
  Stream<List<OutboxEntry>> watchAll() =>
      const Stream<List<OutboxEntry>>.empty();
}

/// Knows which households already have a queued reading.
final class FakeReadingRepository implements ReadingRepository {
  final Map<String, Set<String>> queued = <String, Set<String>>{};

  void markQueued(ConsumerId consumerId, CycleLabel cycle) {
    queued.putIfAbsent(cycle.value, () => <String>{}).add(consumerId.value);
  }

  @override
  Future<Result<Set<ConsumerId>>> queuedConsumerIdsFor(
    CycleLabel cycle,
  ) async => Ok<Set<ConsumerId>>(
    (queued[cycle.value] ?? <String>{})
        .map((String id) => ConsumerId(id))
        .toSet(),
  );

  @override
  Future<Result<bool>> isReadingQueuedFor({
    required ConsumerId consumerId,
    required CycleLabel cycle,
  }) async =>
      Ok<bool>(queued[cycle.value]?.contains(consumerId.value) ?? false);
}

/// A roster held in a list.
final class FakeConsumerRepository implements ConsumerRepository {
  final List<Consumer> households;
  DateTime? refreshedAt;
  int refreshCount = 0;
  int createCount = 0;
  ConsumerNumber? createdConsumerNo;
  String? createdFirstName;
  String? createdLastName;
  String? createdContactNumber;
  AreaId? createdAreaId;
  String? createdPurok;
  ProfileId? createdBy;

  FakeConsumerRepository(this.households);

  @override
  Future<Result<Consumer>> create({
    required ConsumerNumber consumerNo,
    required String firstName,
    required String lastName,
    required AreaId areaId,
    required ProfileId createdBy,
    String? contactNumber,
    String? purok,
  }) async {
    createCount++;
    createdConsumerNo = consumerNo;
    createdFirstName = firstName;
    createdLastName = lastName;
    createdContactNumber = contactNumber;
    createdAreaId = areaId;
    createdPurok = purok;
    this.createdBy = createdBy;

    return Ok<Consumer>(
      Consumer(
        id: const ConsumerId('created-consumer'),
        consumerNo: consumerNo,
        firstName: firstName,
        lastName: lastName,
        contactNumber: contactNumber,
        areaId: areaId,
        purok: purok,
        accountStatus: AccountStatus.active,
        previousReading: Kwh.zero,
      ),
    );
  }

  @override
  Future<Result<List<Consumer>>> areaRoster(AreaId areaId) async =>
      Ok<List<Consumer>>(
        households.where((Consumer c) => c.areaId == areaId).toList(),
      );

  @override
  Future<Result<Consumer?>> byId(ConsumerId id) async {
    for (final Consumer c in households) {
      if (c.id == id) return Ok<Consumer?>(c);
    }
    return const Ok<Consumer?>(null);
  }

  /// The household the signed-in consumer belongs to, when the test is
  /// standing in for a consumer rather than staff.
  Consumer? me;

  @override
  Future<Result<Consumer?>> signedInConsumer() async => Ok<Consumer?>(me);

  @override
  Future<Result<DateTime?>> lastRefreshedAt() async =>
      Ok<DateTime?>(refreshedAt);

  @override
  Future<Result<void>> refreshAreaRoster(AreaId areaId) async {
    refreshCount++;
    return const Ok<void>(null);
  }
}

/// Hands out predictable ids, so a test can assert on them.
final class CountingUuidFactory {
  int _next = 0;

  ClientUuid call() {
    _next++;
    return ClientUuid('test-uuid-$_next');
  }
}

/// A household on the roster, with sensible defaults a test can override.
Consumer household({
  String id = 'consumer-1',
  String areaId = 'area-3',
  Kwh? previousReading,
  CycleLabel? lastReadCycle,
  AccountStatus status = AccountStatus.active,
}) => Consumer(
  id: ConsumerId(id),
  consumerNo: const ConsumerNumber('2019-0917-TUB'),
  firstName: 'Elena',
  lastName: 'Ravelo',
  areaId: AreaId(areaId),
  accountStatus: status,
  previousReading: previousReading ?? Kwh.of(1250),
  purok: 'Purok 3',
  lastReadCycle: lastReadCycle,
);

/// Stand-in for AuthRepository to test auth flows without Supabase.
final class FakeAuthRepository implements AuthRepository {
  final StreamController<AppUser?> _controller =
      StreamController<AppUser?>.broadcast();

  AppUser? user;
  AppFailure? nextSignInFailure;
  int signInCalls = 0;
  int createStaffCalls = 0;
  String? createdStaffUsername;
  String? createdStaffContactNumber;
  StaffRole? createdStaffRole;
  AppFailure? nextCreateStaffFailure;
  Duration? delay;

  FakeAuthRepository({this.user});

  @override
  Future<Result<AppUser>> signIn({
    required String username,
    required String password,
  }) async {
    signInCalls++;
    if (delay != null) {
      await Future<void>.delayed(delay!);
    }
    final failure = nextSignInFailure;
    if (failure != null) {
      return Err<AppUser>(failure);
    }
    final loggedIn =
        user ??
        MeterReaderUser(
          id: const ProfileId('profile-1'),
          username: username,
          firstName: 'Elena',
          lastName: 'Ravelo',
          areaId: const AreaId('area-1'),
          mustChangePassword: false,
        );
    _controller.add(loggedIn);
    return Ok<AppUser>(loggedIn);
  }

  @override
  Future<Result<void>> signOut() async {
    _controller.add(null);
    return const Ok<void>(null);
  }

  @override
  Future<Result<AppUser?>> currentUser() async => Ok<AppUser?>(user);

  @override
  Stream<AppUser?> authChanges() => _controller.stream;

  @override
  Future<Result<void>> changePassword({required String newPassword}) async =>
      const Ok<void>(null);

  @override
  Future<Result<CreatedStaffAccount>> createStaffAccount({
    required String username,
    required String firstName,
    required String lastName,
    required String? contactNumber,
    required StaffRole role,
    required String temporaryPassword,
  }) async {
    createStaffCalls++;
    createdStaffUsername = username;
    createdStaffContactNumber = contactNumber;
    createdStaffRole = role;
    final failure = nextCreateStaffFailure;
    if (failure != null) return Err<CreatedStaffAccount>(failure);
    return Ok<CreatedStaffAccount>(
      CreatedStaffAccount(
        id: const ProfileId('staff-created'),
        username: username,
        firstName: firstName,
        lastName: lastName,
        role: role,
        contactNumber: contactNumber,
      ),
    );
  }

  void dispose() {
    _controller.close();
  }
}

/// Stand-in for AuthController to test LoginScreen directly with Riverpod.
class FakeAuthController extends AuthController {
  int signInCalls = 0;
  AppFailure? failureToReturn;
  Completer<void>? pendingSignIn;

  /// Who is signed in. Null - the default - means nobody, which is what the
  /// login screen tests want. Pass a user to start a test already signed in.
  final AppUser? signedInUser;

  FakeAuthController({
    this.failureToReturn,
    this.pendingSignIn,
    this.signedInUser,
  });

  @override
  Future<AppUser?> build() async => signedInUser;

  @override
  Future<AppFailure?> signIn({
    required String username,
    required String password,
  }) async {
    signInCalls++;
    if (pendingSignIn != null) {
      await pendingSignIn!.future;
    }
    return failureToReturn;
  }
}

/// Bills, without a database. Only the methods the screens under test call
/// are given behaviour; the rest answer honestly that they were not set up.
final class FakeBillRepository implements BillRepository {
  List<AwaitingAmountEntry> queue = <AwaitingAmountEntry>[];
  List<Bill> payableBills = <Bill>[];
  AppFailure? awaitingFailure;
  int awaitingCalls = 0;

  @override
  Future<Result<List<AwaitingAmountEntry>>> awaitingAmount(
    AreaId areaId,
  ) async {
    awaitingCalls++;
    final failure = awaitingFailure;
    if (failure != null) return Err<List<AwaitingAmountEntry>>(failure);
    return Ok<List<AwaitingAmountEntry>>(queue);
  }

  @override
  Future<Result<Bill?>> currentBillFor(ConsumerId consumerId) async =>
      const Ok<Bill?>(null);

  @override
  Future<Result<List<Bill>>> historyFor(
    ConsumerId consumerId, {
    int limit = 12,
  }) async => const Ok<List<Bill>>(<Bill>[]);

  @override
  Future<Result<Bill?>> byId(BillId id) async => const Ok<Bill?>(null);

  @override
  Future<Result<List<Bill>>> payableFor(ConsumerId consumerId) async =>
      Ok<List<Bill>>(payableBills);

  @override
  Future<Result<void>> refreshFor(
    ConsumerId consumerId,
    CycleLabel cycle,
  ) async => const Ok<void>(null);

  List<ConsumerOutstanding> outstanding = <ConsumerOutstanding>[];
  AppFailure? outstandingFailure;

  @override
  Future<Result<List<ConsumerOutstanding>>> outstandingInArea(
    AreaId areaId,
  ) async {
    final failure = outstandingFailure;
    if (failure != null) return Err<List<ConsumerOutstanding>>(failure);
    return Ok<List<ConsumerOutstanding>>(outstanding);
  }
}

/// A sync service that counts calls instead of touching the network.
///
/// SyncService is concrete, so this subclasses it and overrides the three
/// methods that would reach outside the test. The real one checks
/// connectivity, which a widget test cannot answer.
final class FakeSyncService extends SyncService {
  FakeSyncService() : super(FakeOutboxRepository(), const _NoopOutboxGateway());

  int syncCalls = 0;

  @override
  void start() {}

  @override
  Future<void> stop() async {}

  @override
  Future<Result<SyncReport>> syncNow() async {
    syncCalls++;
    return const Ok<SyncReport>(SyncReport.nothingToDo);
  }
}

final class _NoopOutboxGateway implements OutboxGateway {
  const _NoopOutboxGateway();

  @override
  Future<Result<String>> submitReading(RecordReadingOperation o) async =>
      const Ok<String>('');

  @override
  Future<Result<String>> submitPostedAmount(PostAmountOperation o) async =>
      const Ok<String>('');

  @override
  Future<Result<String>> submitPayment(RecordPaymentOperation o) async =>
      const Ok<String>('');

  @override
  Future<Result<String>> submitNotice(IssueNoticeOperation o) async =>
      const Ok<String>('');
}
