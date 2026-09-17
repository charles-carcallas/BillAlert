import 'dart:async';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';
import 'package:billalert/presentation/auth/auth_controller.dart';
import 'package:billalert/presentation/providers.dart';
import 'package:billalert/presentation/reader/consumers_screen.dart';
import 'package:billalert/presentation/reader/roster_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fakes.dart';

/// A meter reader who has just signed in has an empty phone: signing out
/// cleared the cache. Their round must appear without a pull to refresh.
void main() {
  const reader = MeterReaderUser(
    id: ProfileId('reader-1'),
    username: 'ledesma.dormal',
    firstName: 'Ledesma',
    lastName: 'Dormal',
    areaId: AreaId('area-3'),
    mustChangePassword: false,
  );

  late FakeConsumerRepository consumers;

  ProviderContainer signedIn() {
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(
          () => FakeAuthController(signedInUser: reader),
        ),
        consumerRepositoryProvider.overrideWithValue(consumers),
        readingRepositoryProvider.overrideWithValue(FakeReadingRepository()),
        phClockProvider.overrideWithValue(
          FixedPhClock.onPhDate(const PhDate(2026, 9, 9)),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Listens the way an open screen does. Riverpod pauses a provider nobody
  /// listens to, so a bare `read` would never finish.
  Future<T> opened<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
  ) async {
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    while (true) {
      final AsyncValue<T> value = container.read(provider);
      // Riverpod retries a failed provider, which keeps it "loading", so an
      // error counts as finished too.
      if (value.hasError || !value.isLoading) return value.requireValue;
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// The error an open screen would be handed, once there is one.
  Future<Object?> failureOf<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
  ) async {
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    for (var i = 0; i < 1000; i++) {
      final AsyncValue<T> value = container.read(provider);
      if (value.hasError) return value.error;
      await Future<void>.delayed(Duration.zero);
    }
    return null;
  }

  setUp(() {
    consumers = FakeConsumerRepository(<Consumer>[])
      ..serverHouseholds = <Consumer>[household(id: 'h1'), household(id: 'h2')];
  });

  test(
    'the round loads from the server on the first open after sign-in',
    () async {
      final container = signedIn();

      final view = await opened(container, rosterControllerProvider);

      expect(view.roster.entries, hasLength(2));
      expect(consumers.refreshCount, 1);
    },
  );

  test('the Consumers tab loads on first open too', () async {
    final container = signedIn();

    final households = await opened(container, readerHouseholdsProvider);

    expect(households, hasLength(2));
  });

  test('both tabs share one server fetch', () async {
    final container = signedIn();

    await Future.wait(<Future<Object?>>[
      opened(container, rosterControllerProvider),
      opened(container, readerHouseholdsProvider),
    ]);

    expect(consumers.refreshCount, 1);
  });

  test(
    'with no signal and nothing saved, the round says why it is empty',
    () async {
      consumers.refreshFailure = const NetworkFailure();
      final Object? error = await runZonedGuarded<Future<Object?>>(
        () async {
          final container = signedIn();
          return failureOf(container, rosterControllerProvider);
        },
        // Riverpod also reports a provider's failure to the zone. That is
        // the failure this test expects, so it is not a test error.
        (Object reported, StackTrace _) =>
            expect(reported, isA<NetworkFailure>()),
      );

      // The screen shows `failure.message` only for an AppFailure, so it must
      // arrive as one rather than wrapped.
      expect(error, isA<NetworkFailure>());
    },
  );

  test('with no signal, a roster already saved still shows', () async {
    consumers = FakeConsumerRepository(<Consumer>[household(id: 'saved')])
      ..refreshedAt = DateTime.utc(2026, 9, 8)
      ..refreshFailure = const NetworkFailure();
    final container = signedIn();

    final view = await opened(container, rosterControllerProvider);

    expect(view.roster.entries.single.consumer.id, const ConsumerId('saved'));
  });
}
