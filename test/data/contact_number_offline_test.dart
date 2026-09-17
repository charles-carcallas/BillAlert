import 'dart:io';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/consumer_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A household changing its SMS number with no signal.
///
/// Unlike a reading, a number is not saved for later: the server has to
/// accept it, so offline nothing may change and the message must say so.
/// The app's general offline message promises the work will sync, which
/// would leave a household believing texts go to a number the server never
/// received.
void main() {
  test('offline, the number is not changed and the message says so', () async {
    final AppDatabase database = AppDatabase.forTesting(
      NativeDatabase.memory(),
    );
    final SupabaseClient offline = SupabaseClient(
      'https://offline.invalid',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );
    addTearDown(() async {
      await database.close();
      await offline.dispose();
    });

    final Result<String> result = await ConsumerRepositoryImpl(
      database,
      offline,
    ).updateOwnContactNumber('09167928436');

    final AppFailure failure = (result as Err<String>).failure;
    expect(failure, isA<NetworkFailure>());
    expect(failure.message, contains('was not changed'));
    expect(failure.message, isNot(contains('sync')));
  });
}
