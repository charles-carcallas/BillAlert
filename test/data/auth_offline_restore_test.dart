import 'dart:convert';
import 'dart:io';

import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/repositories/auth_repository_impl.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late SupabaseClient client;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    client = SupabaseClient(
      'https://offline.invalid',
      'anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
    );

    final int expiry =
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 1))
            .millisecondsSinceEpoch ~/
        1000;
    String encodePart(Map<String, Object> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final token =
        '${encodePart(<String, Object>{'alg': 'none'})}.'
        '${encodePart(<String, Object>{'exp': expiry})}.signature';

    await client.auth.recoverSession(
      jsonEncode(
        Session(
          accessToken: token,
          expiresIn: 3600,
          refreshToken: 'refresh-token',
          tokenType: 'bearer',
          user: const User(
            id: 'profile-ledesman',
            appMetadata: <String, dynamic>{},
            userMetadata: <String, dynamic>{},
            aud: 'authenticated',
            createdAt: '2026-09-01T00:00:00.000Z',
          ),
        ).toJson(),
      ),
    );

    await database
        .into(database.cacheOwner)
        .insert(
          CacheOwnerCompanion.insert(
            id: const Value<int>(1),
            profileId: 'profile-ledesman',
            username: const Value<String?>('ledesman.dormal'),
            firstName: const Value<String?>('Ledesman'),
            lastName: const Value<String?>('Dormal'),
            mustChangePassword: const Value<bool?>(false),
            role: 'meter_reader',
            areaId: const Value<String?>('area-3'),
            cachedAt: '2026-09-15T00:00:00.000Z',
          ),
        );
  });

  tearDown(() async {
    await database.close();
    await client.dispose();
  });

  test(
    'restores the matching encrypted profile when the network is offline',
    () async {
      final repository = AuthRepositoryImpl(client, database);

      final result = await repository.currentUser();

      expect(result, isA<Ok<AppUser?>>());
      final user = (result as Ok<AppUser?>).value;
      expect(user, isA<MeterReaderUser>());
      expect(user?.username, 'ledesman.dormal');
      expect(user?.firstName, 'Ledesman');
    },
  );

  test('never restores a cache owned by a different session', () async {
    await database
        .update(database.cacheOwner)
        .write(
          const CacheOwnerCompanion(profileId: Value<String>('somebody-else')),
        );
    final repository = AuthRepositoryImpl(client, database);

    final result = await repository.currentUser();

    expect(result, isA<Err<AppUser?>>());
  });
}
