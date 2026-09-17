import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/supabase/failure_mapper.dart';
import 'package:billalert/data/sync/sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/fakes.dart';

/// A phone with no signal at all.
final class _NoSignal implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      const <ConnectivityResult>[ConnectivityResult.none];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream<List<ConnectivityResult>>.empty();
}

/// "Your work is saved and will sync" is a promise. It is kept only for work
/// that is in the outbox, and must not be made about anything else.
void main() {
  test('the ordinary offline message promises nothing', () {
    expect(NetworkFailure.defaultMessage, isNot(contains('saved')));
    expect(NetworkFailure.defaultMessage, isNot(contains('sync')));
  });

  test('a failed read, as the server client reports it, promises nothing', () {
    // No signal while loading a list reaches the app like this.
    final AppFailure failure = FailureMapper.from(
      AuthRetryableFetchException(message: 'Failed host lookup'),
    );

    expect(failure, isA<NetworkFailure>());
    expect(failure.message, isNot(contains('saved')));
  });

  test('syncing the outbox with no signal does say the work is kept', () async {
    final SyncService sync = SyncService(
      FakeOutboxRepository(),
      const NoopOutboxGateway(),
      connectivity: _NoSignal(),
    );

    final Result<SyncReport> result = await sync.syncNow();

    final AppFailure failure = (result as Err<SyncReport>).failure;
    expect(failure.message, contains('saved on this phone'));
  });
}
