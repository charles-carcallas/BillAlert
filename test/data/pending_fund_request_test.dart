import 'dart:convert';
import 'dart:io';
import 'package:billalert/data/local/app_database.dart';
import 'package:billalert/data/local/pending_fund_request.dart';
import 'package:billalert/data/repositories/settlement_repository.dart';
import 'package:billalert/domain/value_objects/money.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'lost reply survives restart/sign-out, retry reuses original request, new cash is blocked',
    () async {
      final dir = await Directory.systemTemp.createTemp('billalert-fund-test');
      final file = File('${dir.path}/fund.sqlite');
      var db = AppDatabase.forTesting(NativeDatabase(file));
      var loseReply = true;
      final received = <String>{};
      final client = SupabaseClient(
        'https://billalert.test',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
        httpClient: MockClient((request) async {
          final p = jsonDecode(request.body) as Map<String, dynamic>;
          received.add(
            p['p_client_uuid'] as String,
          ); // Simulate committed server UUID.
          if (loseReply) throw const SocketException('Reply lost after commit');
          return http.Response(
            '"ledger-id"',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final expiry =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      String part(Object v) =>
          base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
      await client.auth.recoverSession(
        jsonEncode(
          Session(
            accessToken:
                '${part({'alg': 'none'})}.${part({'exp': expiry})}.signature',
            expiresIn: 3600,
            refreshToken: 'test',
            tokenType: 'bearer',
            user: const User(
              id: 'cashier',
              appMetadata: {},
              userMetadata: {},
              aud: 'authenticated',
              createdAt: '2026-10-01T00:00:00Z',
            ),
          ).toJson(),
        ),
      );
      const owner = 'cashier:cashier:area';
      var repo = SettlementRepository(client, db);
      await expectLater(
        repo.entry(
          Money.parse('100'),
          'contribution',
          'Cash added',
          'original',
          owner: owner,
        ),
        throwsA(isA<SocketException>()),
      );
      await db.clearCachedData();
      await db.clearOutbox();
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      repo = SettlementRepository(client, db);
      final pending = await repo.pendingEntry(owner);
      expect(pending?.uuid, 'original');
      expect(await repo.pendingEntry('other:cashier:area'), isNull);
      await expectLater(
        repo.entry(
          Money.parse('100'),
          'contribution',
          'Cash added',
          'replacement',
          owner: owner,
        ),
        throwsStateError,
      );
      expect(received, {'original'});
      loseReply = false;
      await repo.entry(
        Money.parse(pending!.amount),
        pending.kind,
        pending.reason,
        pending.uuid,
        owner: owner,
      );
      expect(received, {'original'});
      expect(await repo.pendingEntry(owner), isNull);
      await expectLater(
        repo.entry(
          Money.parse('100'),
          'contribution',
          'Wrong owner',
          'other',
          owner: 'other:cashier:area',
        ),
        throwsStateError,
      );
      await client.dispose();
      await db.close();
      await dir.delete(recursive: true);
    },
  );

  test('new store refuses conflicting concurrent entries', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final store = FundRequestStore(db);
    const request = PendingFundRequest('100', 'contribution', 'Cash', 'one');
    await store.save('owner', request);
    await store.save('owner', request);
    await expectLater(
      store.save(
        'owner',
        const PendingFundRequest('200', 'contribution', 'Cash', 'two'),
      ),
      throwsStateError,
    );
    expect((await store.read('owner'))?.uuid, 'one');
    await db.close();
  });
}
