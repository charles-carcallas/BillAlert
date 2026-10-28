import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/repositories/account_management_repository.dart';
import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';
import '../auth/linked_household_provider.dart';
import '../common/section_tabs.dart';
import '../common/transfer_guide.dart';
import 'account_management_forms.dart';
import 'account_management_providers.dart';
import 'account_people_list.dart';
import 'linked_account_screen.dart';
import 'staff_assignments.dart';

enum AccountManagementPage { accounts, transfer, activity }

class AccountManagementScreen extends ConsumerStatefulWidget {
  const AccountManagementScreen({
    super.key,
    this.page = AccountManagementPage.accounts,
  });

  final AccountManagementPage page;
  @override
  ConsumerState<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState
    extends ConsumerState<AccountManagementScreen> {
  bool busy = false;
  late String section = switch (widget.page) {
    AccountManagementPage.accounts => 'Staff',
    AccountManagementPage.transfer => 'Transfer',
    AccountManagementPage.activity => 'Activity',
  };
  String get pageTitle => switch (widget.page) {
    AccountManagementPage.accounts => 'Manage accounts',
    AccountManagementPage.transfer => 'Area President transfer',
    AccountManagementPage.activity => 'Account activity',
  };
  String search = '';
  String? message;
  Future<void> createHouseholdSignIn(Map<String, dynamic> h) async {
    if (busy || h['profile_id'] != null || h['account_status'] != 'active') {
      return;
    }
    await Navigator.of(context).push<LinkedAccountCreated>(
      MaterialPageRoute(builder: (_) => LinkedAccountScreen(household: h)),
    );
    if (mounted) ref.invalidate(accountWorkspaceProvider);
  }

  AccountManagementRepository get repository =>
      ref.read(accountManagementRepositoryProvider);
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      if (mounted) {
        setState(() => message = 'Saved. Refreshing the account workspace.');
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) {
        ref.invalidate(linkedHouseholdProvider);
        ref.invalidate(accountWorkspaceProvider);
        ref.invalidate(myPresidentTransfersProvider);
        setState(() => busy = false);
      }
    }
  }

  Future<void> manage(AccountRow person, String action) async {
    if (busy) return;
    final labels = {
      'end_work': 'End work access',
      'restore_work': 'Restore work access',
      'disable_login': 'Disable login',
      'enable_login': 'Enable login',
    };
    final data = await accountForm(
      context,
      title: '${labels[action]}: ${person['username']}',
      fields: const {'reason': 'Reason'},
      reconciliation: action == 'end_work',
      explanation: action == 'disable_login'
          ? 'Emergency login suspension does not require completed reconciliation. Record why. Historical records remain.'
          : 'Work access and household access are separate. Restoring work may be refused if the role is already occupied.',
    );
    if (data != null && mounted) {
      await run(
        () => repository.manage(
          person['id'] as String,
          action,
          data['reason']!,
          data['reconciled'] == 'true',
        ),
      );
    }
  }

  Future<String?> identity(
    bool successor, {
    AccountRow? household,
    String mode = 'existing',
  }) async {
    if (busy) return null;
    final result = await Navigator.of(context).push<LinkedAccountCreated>(
      MaterialPageRoute(
        builder: (_) => LinkedAccountScreen(
          successor: successor,
          household: household,
          householdMode: mode,
        ),
      ),
    );
    if (mounted) ref.invalidate(accountWorkspaceProvider);
    return result?.username;
  }

  Future<void> household(
    AccountRow household,
    List<AccountRow> people,
    String kind,
  ) async {
    if (busy) return;
    final handover = kind == 'handover';

    if (handover || kind == 'same_household') {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replacement login'),
          content: const Text(
            'Does the new household member already have a login? Use it here, or create one for this handover.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'existing'),
              child: const Text('Use existing login'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'create'),
              child: const Text('Create replacement login'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'create') {
        await identity(
          false,
          household: household,
          mode: handover ? 'handover' : 'same_household',
        );
        // Creation includes the reviewed household change atomically.
        return;
      }
    }
    final linked = AccountManagementRepository.rows(
      ref.read(accountWorkspaceProvider).value?['households'] ?? [],
    ).map((h) => h['profile_id']).whereType<String>().toSet();
    final eligible = people.where(
      (p) =>
          p['account_status'] == 'active' &&
          (!handover || !linked.contains(p['id'])) &&
          (kind != 'staff_link' || p['role'] != 'consumer'),
    );
    final profiles = {
      for (final p in eligible)
        p['id'] as String:
            '${p['username']} — ${p['first_name']} ${p['last_name']}',
    };
    final data = await accountForm(
      context,
      title: handover ? 'New unrelated occupant' : 'Link household login',
      fields: {
        'profile': 'Login owner',
        if (handover) ...{
          'consumer_no': 'New consumer number',
          'first_name': 'First name',
          'last_name': 'Last name',
          'opening_reading': 'Opening meter reading',
        },
        'reference': 'Review reference',
      },
      choices: {'profile': profiles},
      explanation: handover
          ? 'Post every unpriced old bill first. The opening reading MUST equal the latest recorded old-household reading (or its initial baseline). A reviewed unrelated occupant gets a fresh household and the current meter. The old login stays linked to the retired household and its history. Select an active, unlinked login registered in this area.'
          : kind == 'same_household'
          ? 'Only a reviewed change within the same household. Its history stays with it. Never use this for an unrelated occupant.'
          : 'Links staff to their own household. An occupied household cannot be replaced with a staff link.',
    );
    if (data == null || !mounted) return;
    await run(
      () => handover
          ? repository.handover(
              household['id'] as String,
              data['consumer_no']!,
              data['first_name']!,
              data['last_name']!,
              data['profile']!,
              data['reference']!,
              num.parse(data['opening_reading']!),
            )
          : repository.link(
              household['id'] as String,
              data['profile']!,
              kind,
              data['reference']!,
            ),
    );
  }

  Future<void> waiver(AccountRow reader, List<AccountRow> households) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    List<AccountRow> history;
    try {
      history = await repository.waiverHistory(reader['id'] as String);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          message = 'Could not load waiver history. Connect and refresh.';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => busy = false);
    final active = history.where((h) => h['ended_at'] == null).toList();
    final own = households
        .where(
          (h) =>
              h['profile_id'] == reader['id'] &&
              h['account_status'] == 'active',
        )
        .toList();
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('BOHECO coverage: ${reader['username']}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Covered by BOHECO is not a payment or receipt. Coverage applies only to newly priced eligible bills, with no backfill. End existing coverage before replacement.',
                ),
                if (history.isEmpty) const Text('No assignments.'),
                for (final h in history)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'From ${h['start_month']} · meter ${h['meter_serial_no']}',
                    ),
                    subtitle: Text(
                      h['ended_at'] == null
                          ? 'Active'
                          : 'Ended ${h['ended_at']} · ${h['end_reason']}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (active.isNotEmpty)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'end'),
              child: const Text('End coverage'),
            ),
          if (active.isEmpty &&
              own.isNotEmpty &&
              reader['staff_enabled'] == true &&
              reader['account_status'] == 'active')
            FilledButton(
              onPressed: () => Navigator.pop(context, 'assign'),
              child: const Text('Assign own household'),
            ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'end') {
      final data = await accountForm(
        context,
        title: 'End BOHECO coverage',
        fields: const {'reason': 'Reason'},
        explanation:
            'Existing covered bills stay unchanged. Future bills no longer qualify.',
      );
      if (data != null && mounted) {
        await run(
          () => repository.endWaiver(
            active.first['id'] as String,
            data['reason']!,
          ),
        );
      }
    } else {
      final data = await accountForm(
        context,
        title: 'Assign BOHECO coverage',
        fields: const {
          'household': 'Own linked household',
          'month': 'Start month (YYYY-MM-01)',
        },
        choices: {
          'household': {
            for (final h in own) h['id'] as String: '${h['consumer_no']}',
          },
        },
        explanation:
            'Start on the first of the current or a future month. Only bills newly priced after this assignment qualify.',
      );
      if (data != null && mounted) {
        await run(
          () => repository.assignWaiver(
            reader['id'] as String,
            data['household']!,
            data['month']!,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    if (user is! AdminUser || !user.hasWorkAccess) {
      return Scaffold(
        appBar: AppBar(title: Text(pageTitle)),
        body: const Center(
          child: Text('Active Area President access is required.'),
        ),
      );
    }
    final workspace = ref.watch(accountWorkspaceProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: busy
                ? null
                : () => ref.invalidate(accountWorkspaceProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: workspace.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () => ref.invalidate(accountWorkspaceProvider),
              child: const Text(
                'Could not load accounts. Connect and refresh.',
              ),
            ),
          ),
          data: (data) {
            final people = AccountManagementRepository.rows(data['people']);
            final households = AccountManagementRepository.rows(
              data['households'],
            );
            final visiblePeople = people
                .where(
                  (p) => '${p['first_name']} ${p['last_name']} ${p['username']}'
                      .toLowerCase()
                      .contains(search),
                )
                .toList();
            final visibleHouseholds = households
                .where(
                  (h) =>
                      '${h['consumer_no']} ${h['first_name']} ${h['last_name']}'
                          .toLowerCase()
                          .contains(search),
                )
                .toList();
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    if (busy) const LinearProgressIndicator(),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(message!),
                      ),
                    if (widget.page == AccountManagementPage.accounts)
                      SectionTabs(
                        labels: const ['Staff', 'People', 'Households'],
                        selected: section,
                        onChanged: (label) => setState(() {
                          section = label;
                          search = '';
                        }),
                      ),
                    const SizedBox(height: 24),
                    if (section == 'Staff')
                      StaffAssignments(
                        people: people,
                        area: user.areaId!.value,
                      ),
                    if (section == 'People' || section == 'Households') ...[
                      TextField(
                        key: ValueKey(section),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: section == 'People'
                              ? 'Search name or username'
                              : 'Search name or consumer number',
                        ),
                        onChanged: (value) =>
                            setState(() => search = value.trim().toLowerCase()),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (section == 'People') ...[
                      Text(
                        search.isEmpty
                            ? '${people.length} people'
                            : '${visiblePeople.length} of ${people.length} people',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (visiblePeople.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No matching people.'),
                        ),
                      if (visiblePeople.isNotEmpty)
                        AccountPeopleList(
                          people: visiblePeople,
                          households: households,
                          currentUserId: user.id.value,
                          onAction: (person, action) => action == 'waiver'
                              ? waiver(person, households)
                              : manage(person, action),
                        ),
                    ],
                    if (section == 'Households') ...[
                      Text(
                        '${households.length} households',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Household records, linked logins and reviewed handovers.',
                      ),
                      const SizedBox(height: 20),
                      if (visibleHouseholds.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No matching households.'),
                        ),
                      for (final h in visibleHouseholds)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(
                              20,
                              12,
                              12,
                              12,
                            ),
                            title: Text(
                              '${h['consumer_no']} · ${h['first_name']} ${h['last_name']}',
                            ),
                            subtitle: Text(
                              'Meter ${h['meter_serial_no'] ?? 'none'} · ${h['account_status']} · ${h['profile_id'] == null ? 'No login linked' : 'Login linked'}',
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (a) => a == 'create_sign_in'
                                  ? createHouseholdSignIn(h)
                                  : household(h, people, a),
                              itemBuilder: (_) => [
                                if (h['profile_id'] == null &&
                                    h['account_status'] == 'active')
                                  const PopupMenuItem(
                                    value: 'create_sign_in',
                                    child: Text('Finish account setup'),
                                  ),
                                const PopupMenuItem(
                                  value: 'staff_link',
                                  child: Text('Link own staff household'),
                                ),
                                const PopupMenuItem(
                                  value: 'same_household',
                                  child: Text('Reviewed same-household link'),
                                ),
                                const PopupMenuItem(
                                  value: 'handover',
                                  child: Text('Unrelated occupant handover'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (section == 'Transfer') ...[
                      const TransferGuide(),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => identity(true),
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Nominate a successor'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/account/transfer'),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Review my transfers'),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Transfer records',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (AccountManagementRepository.rows(
                        data['transfers'],
                      ).isEmpty)
                        const Text('No transfers have been started.'),
                      for (final t in AccountManagementRepository.rows(
                        data['transfers'],
                      ))
                        ListTile(
                          title: Text('${t['status']}'),
                          subtitle: Text('${t['reason']} · ${t['created_at']}'),
                        ),
                    ],
                    if (section == 'Activity') ...[
                      Text(
                        'Account activity',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'A record of account and household changes in your area.',
                      ),
                      const SizedBox(height: 20),
                      if (AccountManagementRepository.rows(
                        data['audit'],
                      ).isEmpty)
                        const Text('No account changes yet.'),
                      for (final a in AccountManagementRepository.rows(
                        data['audit'],
                      ))
                        ListTile(
                          title: Text('${a['action']}'.replaceAll('_', ' ')),
                          subtitle: Text('${a['reason']} · ${a['created_at']}'),
                        ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
