import 'package:supabase_flutter/supabase_flutter.dart';

typedef AccountRow = Map<String, dynamic>;

class AccountManagementException implements Exception {
  const AccountManagementException(this.message, {this.safeToRetry = false});
  final String message;
  final bool safeToRetry;
  @override
  String toString() => message;
}

/// Server-only operations: never queued or automatically retried.
class AccountManagementRepository {
  AccountManagementRepository(this.client);
  final SupabaseClient client;

  Future<AccountRow> workspace() async => Map<String, dynamic>.from(
    await client.rpc('fn_account_workspace') as Map,
  );

  Future<List<AccountRow>> transfers() async =>
      rows(await client.rpc('fn_my_president_transfers'));

  static List<AccountRow> rows(dynamic value) => (value as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  Future<void> manage(
    String target,
    String action,
    String reason,
    bool reconciled,
  ) => {'disable_login', 'enable_login'}.contains(action)
      ? createIdentity({'action': action, 'target': target, 'reason': reason})
      : _write('fn_manage_account', {
          'p_target': target,
          'p_action': action,
          'p_reason': reason,
          'p_reconciled': reconciled,
        });

  Future<List<AccountRow>> waiverHistory(String reader) async => rows(
    await client.rpc(
      'fn_reader_waiver_history',
      params: {'p_reader_id': reader},
    ),
  );
  Future<void> assignWaiver(String reader, String consumer, String month) =>
      _write('fn_assign_reader_waiver', {
        'p_reader_id': reader,
        'p_consumer_id': consumer,
        'p_start_month': month,
      });
  Future<void> endWaiver(String assignment, String reason) => _write(
    'fn_end_reader_waiver',
    {'p_assignment_id': assignment, 'p_reason': reason},
  );

  Future<void> link(
    String consumer,
    String profile,
    String kind,
    String reference,
  ) => _write('fn_link_household', {
    'p_consumer': consumer,
    'p_profile': profile,
    'p_kind': kind,
    'p_reference': reference,
  });

  Future<void> handover(
    String oldConsumer,
    String consumerNo,
    String firstName,
    String lastName,
    String profile,
    String reference,
    num openingReading,
  ) => _write('fn_household_handover', {
    'p_old_consumer': oldConsumer,
    'p_new_consumer_no': consumerNo,
    'p_first_name': firstName,
    'p_last_name': lastName,
    'p_profile': profile,
    'p_reference': reference,
    'p_opening_reading': openingReading,
  });

  Future<void> transfer(String id, String action, {bool reconciled = false}) {
    if (!{'accept', 'complete', 'cancel'}.contains(action)) {
      throw ArgumentError.value(action);
    }
    return _write('fn_${action}_president_transfer', {
      'p_transfer': id,
      if (action == 'complete') 'p_reconciled': reconciled,
    });
  }

  Future<void> createIdentity(AccountRow body) async {
    await _createIdentity(body);
  }

  Future<String> createLinkedAccount(AccountRow body) async {
    final data = await _createIdentity(body);
    final id = data['id'];
    if (id is! String || id.isEmpty) {
      throw const AccountManagementException(uncertain);
    }
    return id;
  }

  Future<void> assignStaff({
    required String operation,
    required String role,
    required AccountRow replacement,
    required AccountRow? outgoing,
    required bool reconciled,
  }) => _write('fn_assign_staff', {
    'p_operation': operation,
    'p_role': role,
    'p_replacement': replacement['id'],
    'p_replacement_version': replacement['access_version'],
    'p_outgoing': outgoing?['id'],
    'p_outgoing_version': outgoing?['access_version'],
    'p_reconciled': reconciled,
  });

  Future<AccountRow> _createIdentity(AccountRow body) async {
    try {
      final response = await client.functions.invoke(
        'manage-accounts',
        body: body,
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        throw AccountManagementException(
          data is Map ? '${data['message'] ?? uncertain}' : uncertain,
          safeToRetry:
              data is Map &&
              {
                'validation',
                'rejected',
                'conflict',
                'permission',
              }.contains(data['kind']),
        );
      }
      return Map<String, dynamic>.from(data);
    } on AccountManagementException {
      rethrow;
    } catch (_) {
      throw const AccountManagementException(uncertain);
    }
  }

  static const uncertain =
      'The result could not be confirmed. Refresh and check '
      'the account or transfer before trying again. Do not repeat blindly; '
      'ask support to check the username if it is missing.';

  Future<void> _write(String name, AccountRow params) async {
    try {
      await client.rpc(name, params: params);
    } on PostgrestException catch (e) {
      throw AccountManagementException(
        '${e.message} Refresh before trying again.',
      );
    } catch (_) {
      throw const AccountManagementException(uncertain);
    }
  }
}
