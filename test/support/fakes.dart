import 'dart:async';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/outbox/outbox_entry.dart';
import 'package:billalert/domain/outbox/outbox_operation.dart';
import 'package:billalert/domain/repositories/auth_repository.dart';
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
  factory FixedPhClock.onPhDate(PhDate date) => FixedPhClock(
        DateTime.utc(date.year, date.month, date.day, 4),
      );

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
            .map((OutboxOperation op) => OutboxEntry(
                  operation: op,
                  status: OutboxStatus.pending,
                  attempts: 0,
                  createdAt: op.capturedAt,
                ))
            .toList(),
      );

  @override
  Future<Result<List<OutboxEntry>>> all() => pending();

  @override
  Future<Result<void>> markSyncing(ClientUuid clientUuid) async =>
      const Ok<void>(null);

  @override
  Future<Result<void>> markSynced(ClientUuid clientUuid, String serverId) async =>
      const Ok<void>(null);

  @override
  Future<Result<void>> markFailed(ClientUuid clientUuid, String reason) async =>
      const Ok<void>(null);

  @override
  Stream<List<OutboxEntry>> watchAll() => const Stream<List<OutboxEntry>>.empty();
}

/// Knows which households already have a queued reading.
final class FakeReadingRepository implements ReadingRepository {
  final Map<String, Set<String>> queued = <String, Set<String>>{};

  void markQueued(ConsumerId consumerId, CycleLabel cycle) {
    queued.putIfAbsent(cycle.value, () => <String>{}).add(consumerId.value);
  }

  @override
  Future<Result<Set<ConsumerId>>> queuedConsumerIdsFor(CycleLabel cycle) async =>
      Ok<Set<ConsumerId>>(
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

  FakeConsumerRepository(this.households);

  @override
  Future<Result<List<Consumer>>> areaRoster(AreaId areaId) async =>
      Ok<List<Consumer>>(
        households
            .where((Consumer c) => c.areaId == areaId)
            .toList(),
      );

  @override
  Future<Result<Consumer?>> byId(ConsumerId id) async {
    for (final Consumer c in households) {
      if (c.id == id) return Ok<Consumer?>(c);
    }
    return const Ok<Consumer?>(null);
  }

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
}) =>
    Consumer(
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
    final loggedIn = user ??
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
