import 'dart:convert';
import 'package:billalert/data/repositories/account_management_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'assignment sends expected identities, versions and explicit reconciliation',
    () async {
      late http.Request sent;
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response('', 204, request: request);
        }),
      );
      await AccountManagementRepository(client).assignStaff(
        operation: 'operation',
        role: 'cashier',
        replacement: {'id': 'incoming', 'access_version': 4},
        outgoing: {'id': 'outgoing', 'access_version': 9},
        reconciled: true,
      );
      expect(sent.url.path, '/rest/v1/rpc/fn_assign_staff');
      expect(jsonDecode(sent.body), {
        'p_operation': 'operation',
        'p_role': 'cashier',
        'p_replacement': 'incoming',
        'p_replacement_version': 4,
        'p_outgoing': 'outgoing',
        'p_outgoing_version': 9,
        'p_reconciled': true,
      });
      await client.dispose();
    },
  );
  test(
    'new candidate uses existing identity service and returns identity for selection',
    () async {
      late http.Request sent;
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            '{"ok":true,"id":"new-id"}',
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final id = await AccountManagementRepository(client).createLinkedAccount({
        'action': 'create_account',
        'household': {
          'mode': 'new',
          'consumer_no': 'TEST-1',
          'confirmed': true,
        },
        'role': 'consumer',
        'username': 'new.member',
        'first_name': 'New',
        'last_name': 'Member',
        'temporary_password': 'test-only',
      });
      expect(id, 'new-id');
      expect(sent.url.path, '/functions/v1/manage-accounts');
      expect((jsonDecode(sent.body) as Map)['action'], 'create_account');
      expect((jsonDecode(sent.body) as Map)['household']['confirmed'], isTrue);
      await client.dispose();
    },
  );
  test(
    'handover preserves reading and exact profile/reference contract',
    () async {
      late http.Request sent;
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((r) async {
          sent = r;
          return http.Response('', 204, request: r);
        }),
      );
      await AccountManagementRepository(
        client,
      ).handover('old', 'new-no', 'First', 'Last', 'profile', 'review', 123.5);
      expect(sent.url.path, '/rest/v1/rpc/fn_household_handover');
      expect(jsonDecode(sent.body), {
        'p_old_consumer': 'old',
        'p_new_consumer_no': 'new-no',
        'p_first_name': 'First',
        'p_last_name': 'Last',
        'p_profile': 'profile',
        'p_reference': 'review',
        'p_opening_reading': 123.5,
      });
      await client.dispose();
    },
  );
  test('login actions use Edge rather than only updating database', () async {
    late http.Request sent;
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((r) async {
        sent = r;
        return http.Response(
          '{"ok":true}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await AccountManagementRepository(
      client,
    ).manage('target', 'disable_login', 'emergency', false);
    expect(sent.url.path, '/functions/v1/manage-accounts');
    expect(jsonDecode(sent.body), {
      'action': 'disable_login',
      'target': 'target',
      'reason': 'emergency',
    });
    await client.dispose();
  });
  test('uncertain identity response is surfaced without retry', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((r) async {
        calls++;
        return http.Response(
          '{"ok":false,"kind":"uncertain","message":"Do not repeat; account may remain."}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await expectLater(
      AccountManagementRepository(
        client,
      ).createIdentity({'action': 'create_successor'}),
      throwsA(
        isA<AccountManagementException>().having(
          (e) => e.message,
          'message',
          contains('may remain'),
        ),
      ),
    );
    expect(calls, 1);
    await client.dispose();
  });
  test(
    'completion sends explicit reconciliation and never infers it',
    () async {
      final bodies = <dynamic>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        httpClient: MockClient((r) async {
          bodies.add(jsonDecode(r.body));
          return http.Response('', 204, request: r);
        }),
      );
      final repository = AccountManagementRepository(client);
      await repository.transfer('transfer', 'complete');
      await repository.transfer('transfer', 'complete', reconciled: true);
      expect(bodies, [
        {'p_transfer': 'transfer', 'p_reconciled': false},
        {'p_transfer': 'transfer', 'p_reconciled': true},
      ]);
      await client.dispose();
    },
  );
}
