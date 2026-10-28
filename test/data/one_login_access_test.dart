import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/data/dto/profile_dto.dart';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/local/query_cache.dart';
import 'package:billalert/data/repositories/auth_repository_impl.dart';
import 'package:billalert/data/repositories/bill_repository_impl.dart';
import 'package:billalert/data/repositories/consumer_repository_impl.dart';
import 'package:billalert/data/repositories/notice_repository_impl.dart';
import 'package:billalert/domain/entities/app_user.dart';
import 'package:billalert/domain/entities/consumer.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase db;
  late SupabaseClient client;
  late AuthRepositoryImpl auth;
  late Map<String, dynamic> profile;
  var offline = false;
  var getUserCalls = 0;
  var banned = false;
  Completer<void>? profileDelay;
  final requests = <Uri>[];
  const user = User(
    id: 'staff-profile',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );

  setUp(() async {
    offline = false;
    profileDelay = null;
    getUserCalls = 0;
    banned = false;
    requests.clear();
    profile = {
      'id': user.id,
      'username': 'staff',
      'first_name': 'Staff',
      'last_name': 'Member',
      'role': 'admin',
      'area_id': 'area',
      'must_change_password': false,
      'account_status': 'active',
      'staff_enabled': true,
      'access_version': 0,
    };
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = SupabaseClient(
      'https://test.invalid',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
      httpClient: MockClient((request) async {
        requests.add(request.url);
        if (offline) throw const SocketException('offline');
        Object? result = <String, dynamic>{};
        if (request.url.path.endsWith('/user')) {
          getUserCalls++;
          if (banned) {
            return http.Response(
              jsonEncode({'code': 'user_banned', 'msg': 'User is banned'}),
              403,
              request: request,
              headers: {
                'content-type': 'application/json',
                'x-supabase-api-version': '2024-01-01',
              },
            );
          }
          result = user.toJson();
        } else if (request.url.path.endsWith('/profiles')) {
          result = Map<String, dynamic>.from(profile);
          await profileDelay?.future;
        } else if (request.url.path.endsWith('/consumers')) {
          result = [
            {
              'id': 'own',
              'consumer_no': 'H1',
              'first_name': 'Own',
              'last_name': 'Household',
              'area_id': 'area',
              'account_status': 'inactive',
              'opening_reading': 72.5,
            },
          ];
        } else if (request.url.path.endsWith('/meter_readings')) {
          result = [];
        } else if (request.url.path.endsWith('/v_bill_status')) {
          result = null;
        } else if (request.url.path.endsWith(
          '/v_active_disconnection_warnings',
        )) {
          result = [];
        }
        return http.Response(
          jsonEncode(result),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final expiry =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
        1000;
    String part(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    await client.auth.recoverSession(
      jsonEncode(
        Session(
          accessToken: '${part({'alg': 'none'})}.${part({'exp': expiry})}.sig',
          refreshToken: 'refresh',
          tokenType: 'bearer',
          expiresIn: 3600,
          user: user,
        ).toJson(),
      ),
    );
    auth = AuthRepositoryImpl(client, db);
  });
  tearDown(() async {
    await client.dispose();
    await db.close();
  });

  test(
    'disabled staff keeps historical role and forced password but no work access',
    () {
      profile['staff_enabled'] = false;
      profile['must_change_password'] = true;
      final mapped = ProfileDto.fromJson(profile)!;
      expect(mapped, isA<ConsumerUser>());
      expect(mapped.historicalRole, 'admin');
      expect(mapped.hasWorkAccess, false);
      expect(mapped.mustChangePassword, true);
      profile['account_status'] = 'inactive';
      expect(ProfileDto.fromJson(profile), isNull);
    },
  );

  test(
    'staff household query filters profile, preserves archived service history and caches only that link',
    () async {
      final repository = ConsumerRepositoryImpl(db, client);
      final found = await repository.signedInConsumer();
      expect((found as Ok<Consumer?>).value!.id.value, 'own');
      final query = requests.last;
      expect(query.queryParameters['profile_id'], 'eq.staff-profile');
      expect(query.queryParameters.containsKey('account_status'), false);
      offline = true;
      final cached = await repository.signedInConsumer();
      expect((cached as Ok<Consumer?>).value!.id.value, 'own');
    },
  );

  test(
    'same-profile access version clears household and work cache before next read',
    () async {
      await auth.currentUser();
      await ConsumerRepositoryImpl(db, client).signedInConsumer();
      await QueryCache(db).rows(
        'work',
        () async => [
          {'secret': 'old'},
        ],
      );
      final epoch = db.cacheEpoch;
      profile['access_version'] = 1;
      expect(await auth.confirmSession(), isA<Ok<void>>());
      expect(getUserCalls, 1);
      expect(db.cacheEpoch, greaterThan(epoch));
      final keys = (await db.select(db.cachedQueries).get()).map(
        (r) => r.queryKey,
      );
      expect(keys, isNot(contains('work')));
      expect(keys, isNot(contains('own-household:staff-profile')));
      expect(
        ((await auth.currentUser()) as Ok<AppUser?>).value!.accessVersion,
        1,
      );
    },
  );

  test('personal detail queries include household even for staff', () async {
    await BillRepositoryImpl(db, client).byId(
      const BillId('someone-elses-bill'),
      consumerId: const ConsumerId('own'),
    );
    expect(requests.last.queryParameters['consumer_id'], 'eq.own');
    await NoticeRepositoryImpl(db, client).byId(
      const NoticeId('someone-elses-notice'),
      consumerId: const ConsumerId('own'),
    );
    expect(requests.last.queryParameters['consumer_id'], 'eq.own');
  });

  test('revoked staff remains household-only after offline restart', () async {
    await auth.currentUser();
    profile['staff_enabled'] = false;
    profile['access_version'] = 2;
    await auth.confirmSession();
    offline = true;
    final restored = await AuthRepositoryImpl(client, db).currentUser();
    final mapped = (restored as Ok<AppUser?>).value!;
    expect(mapped, isA<ConsumerUser>());
    expect(mapped.historicalRole, 'admin');
    expect(mapped.accessVersion, 2);
  });

  test(
    'inactive account fails confirmation despite a valid Auth user',
    () async {
      profile['account_status'] = 'inactive';
      final result = await auth.confirmSession();
      expect(result, isA<Err<void>>());
      expect((result as Err<void>).failure, isA<AuthFailure>());
      expect(getUserCalls, 1);
    },
  );

  test(
    'Auth ban invalidates the already-open session without loading profile',
    () async {
      await auth.currentUser();
      banned = true;
      requests.clear();
      final result = await auth.confirmSession();
      expect(result, isA<Err<void>>());
      final failure = (result as Err<void>).failure;
      expect(failure, isA<AuthFailure>());
      expect(failure.message, AuthFailure.disabledMessage);
      expect(requests.any((uri) => uri.path.endsWith('/profiles')), isFalse);
    },
  );

  test('late profile response cannot claim cache after sign-out', () async {
    profileDelay = Completer<void>();
    final pending = auth.currentUser();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await auth.signOut();
    profileDelay!.complete();
    expect(await pending, isA<Err<AppUser?>>());
    expect(await db.select(db.cacheOwner).get(), isEmpty);
  });

  test('in-flight cache response is rejected after access changes', () async {
    await auth.currentUser();
    final delayed = Completer<List<Map<String, dynamic>>>();
    final pending = QueryCache(db).rows('late', () => delayed.future);
    final assertion = expectLater(pending, throwsA(isA<AuthFailure>()));
    profile['access_version'] = 1;
    await auth.confirmSession();
    delayed.complete([
      {'old': true},
    ]);
    await assertion;
    expect(
      (await db.select(db.cachedQueries).get()).any(
        (r) => r.queryKey == 'late',
      ),
      false,
    );
  });

  test('new service roster starts at opening meter reading', () async {
    final repository = ConsumerRepositoryImpl(db, client);
    expect(
      await repository.refreshAreaRoster(const AreaId('area')),
      isA<Ok<void>>(),
    );
    final roster = await repository.areaRoster(const AreaId('area'));
    expect(
      (roster as Ok<List<Consumer>>).value.single.previousReading,
      equals(
        (await repository.byId(const ConsumerId('own')) as Ok<Consumer?>)
            .value!
            .previousReading,
      ),
    );
    final row = await db.select(db.cachedConsumers).getSingle();
    expect(row.previousReadingHundredths, 7250);
    expect(
      requests.first.queryParameters['select'],
      contains('opening_reading'),
    );
  });
}
