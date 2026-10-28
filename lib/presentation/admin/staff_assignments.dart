import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/account_management_repository.dart';
import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import 'account_management_providers.dart';
import 'linked_account_screen.dart';
import 'staff_household_setup.dart';
import 'temporary_password_card.dart';

String _name(AccountRow p) => '${p['first_name']} ${p['last_name']}';
String _roleName(String role) =>
    role == 'meter_reader' ? 'Meter Reader' : 'Cashier';
IconData _roleIcon(String role) => role == 'meter_reader'
    ? Icons.speed_outlined
    : Icons.point_of_sale_outlined;

AccountRow? _holder(List<AccountRow> people, String role, String area) {
  for (final p in people) {
    if (p['role'] == role &&
        p['account_status'] == 'active' &&
        p['staff_enabled'] == true &&
        (p['area_id'] == null || p['area_id'] == area)) {
      return p;
    }
  }
  return null;
}

/// The normal staff handover entry point. Individual login controls remain in People.
class StaffAssignments extends ConsumerWidget {
  const StaffAssignments({required this.people, required this.area, super.key});
  final List<AccountRow> people;
  final String area;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your staff', style: theme.textTheme.titleLarge),
        const SizedBox(height: 6),
        const Text('Choose who handles readings and collections in your area.'),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 640
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final role in ['meter_reader', 'cashier'])
                  SizedBox(
                    width: width,
                    child: _PositionCard(
                      role: role,
                      person: _holder(people, role, area),
                      onChange: () async {
                        final changed = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => StaffAssignmentScreen(role: role),
                          ),
                        );
                        if (!context.mounted) return;
                        ref.invalidate(accountWorkspaceProvider);
                        if (changed == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_roleName(role)} assignment saved.',
                              ),
                            ),
                          );
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          'Past readings and receipts stay with the person who recorded them.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.role,
    required this.person,
    required this.onChange,
  });
  final String role;
  final AccountRow? person;
  final VoidCallback onChange;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(_roleIcon(role), color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _roleName(role),
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            person == null ? 'Not assigned' : _name(person!),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            person == null
                ? 'Choose someone to fill this position.'
                : '@${person!['username']}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onChange,
            icon: Icon(
              person == null
                  ? Icons.person_add_alt_1_outlined
                  : Icons.swap_horiz_rounded,
            ),
            label: Text(
              person == null
                  ? 'Assign ${_roleName(role)}'
                  : 'Change ${_roleName(role)}',
            ),
          ),
        ],
      ),
    );
  }
}

class StaffAssignmentScreen extends ConsumerStatefulWidget {
  const StaffAssignmentScreen({required this.role, super.key});
  final String role;
  @override
  ConsumerState<StaffAssignmentScreen> createState() => _StaffAssignmentState();
}

class _StaffAssignmentState extends ConsumerState<StaffAssignmentScreen> {
  final scroll = ScrollController();
  List<AccountRow> people = [];
  List<AccountRow> households = [];
  AccountRow? outgoing;
  AccountRow? selected;
  AppUser? actor;
  LinkedAccountCreated? created;
  String search = '';
  String? error;
  bool loading = true, busy = false, reconciled = false, needsRefresh = false;
  String? operation;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  void showTop() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && scroll.hasClients) scroll.jumpTo(0);
  });

  @override
  void initState() {
    super.initState();
    actor = ref.read(authControllerProvider).value;
    load();
  }

  void checkSession() {
    final current = ref.read(authControllerProvider).value;
    if (current is! AdminUser ||
        current.areaId == null ||
        current.accessScope != actor?.accessScope) {
      throw const AccountManagementException(
        'Your work access changed. Reopen Manage accounts.',
      );
    }
    if (!ref.read(networkStatusProvider).isOnline) {
      throw const AccountManagementException(
        'Staff changes need a connection. Connect and refresh.',
      );
    }
  }

  Future<void> load({String? choose}) async {
    if (busy) return;
    setState(() {
      loading = true;
      error = null;
      selected = null;
      reconciled = false;
    });
    try {
      checkSession();
      final data = await ref
          .read(accountManagementRepositoryProvider)
          .workspace();
      if (!mounted) return;
      checkSession();
      final rows = AccountManagementRepository.rows(data['people']);
      households = AccountManagementRepository.rows(data['households']);
      if (rows.any((p) => p['access_version'] == null)) {
        throw const AccountManagementException(
          'Staff assignments need the latest database update. Apply the reviewed staff-assignment migration first.',
        );
      }
      final area = actor!.areaId!.value;
      outgoing = _holder(rows, widget.role, area);
      people = rows
          .where(
            (p) =>
                p['area_id'] == area &&
                p['account_status'] == 'active' &&
                p['role'] != 'admin' &&
                (p['role'] == 'consumer' || p['staff_enabled'] == false),
          )
          .toList();
      if (choose != null) {
        for (final p in people) {
          if (p['id'] == choose) selected = p;
        }
      }
      needsRefresh = false;
      operation = ref.read(clientUuidFactoryProvider)().value;
    } catch (e) {
      if (mounted) error = e.toString();
    }
    if (mounted) {
      setState(() => loading = false);
      showTop();
    }
  }

  Future<void> addPerson() async {
    final result = await Navigator.of(context).push<LinkedAccountCreated>(
      MaterialPageRoute(
        builder: (_) => const LinkedAccountScreen(candidate: true),
      ),
    );
    if (!mounted) return;
    if (result != null) created = result;
    // Also refresh after an uncertain creation; never submit it again automatically.
    await load(choose: result?.id);
  }

  bool hasHousehold(AccountRow p) =>
      households.any((h) => h['profile_id'] == p['id']);
  bool get householdsReady =>
      selected != null &&
      hasHousehold(selected!) &&
      (outgoing == null || hasHousehold(outgoing!));

  Future<void> disableOutgoing() async {
    if (outgoing == null || busy || !reconciled) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable outgoing login?'),
        content: Text(
          '${_name(outgoing!)} will no longer be able to sign in. Their past work stays recorded. The replacement is appointed only after you review and confirm again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disable login'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      checkSession();
      await ref
          .read(accountManagementRepositoryProvider)
          .manage(
            outgoing!['id'] as String,
            'disable_login',
            'Reviewed staff replacement; no household to retain',
            true,
          );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
      return;
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await load(choose: selected?['id'] as String?);
  }

  Future<void> save() async {
    if (busy ||
        selected == null ||
        !reconciled ||
        needsRefresh ||
        !householdsReady) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    bool requested = false;
    try {
      checkSession();
      requested = true;
      await ref
          .read(accountManagementRepositoryProvider)
          .assignStaff(
            operation: operation!,
            role: widget.role,
            replacement: selected!,
            outgoing: outgoing,
            reconciled: reconciled,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          needsRefresh = requested;
        });
        showTop();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = people.where(
      (p) => '${_name(p)} ${p['username']}'.toLowerCase().contains(search),
    );
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${selected == null ? 'Choose' : 'Review'} ${_roleName(widget.role)}',
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (busy) const LinearProgressIndicator(),
                      if (error != null) ...[
                        _InlineMessage(text: error!, isError: true),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: busy ? null : () => load(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh accounts'),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (created != null) ...[
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: Text('New login: @${created!.username}'),
                          subtitle: const Text(
                            'Keep these details for the new person.',
                          ),
                          children: [
                            TemporaryPasswordCard(
                              username: created!.username,
                              temporaryPassword: created!.password,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (selected == null && error == null) ...[
                        Text(
                          'Who will take this position?',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Use their existing login, or add someone new.',
                        ),
                        const SizedBox(height: 20),
                        if (outgoing != null) ...[
                          _PersonSummary(
                            label: 'Current ${_roleName(widget.role)}',
                            person: outgoing!,
                            icon: _roleIcon(widget.role),
                          ),
                          const SizedBox(height: 24),
                        ],
                        TextField(
                          decoration: const InputDecoration(
                            hintText: 'Search name or username',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (v) =>
                              setState(() => search = v.trim().toLowerCase()),
                        ),
                        const SizedBox(height: 16),
                        if (visible.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('No available people found.'),
                          ),
                        for (final person in visible)
                          Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: const Icon(Icons.person_outline),
                              title: Text(_name(person)),
                              subtitle: Text('@${person['username']}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                setState(() {
                                  selected = person;
                                  reconciled = false;
                                });
                                showTop();
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: addPerson,
                          icon: const Icon(Icons.person_add_alt_1_outlined),
                          label: const Text('Add new person'),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Only active accounts in your area without a current staff position appear here.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (selected != null) ...[
                        Text(
                          'Confirm the handover',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 20),
                        if (outgoing != null) ...[
                          _PersonSummary(
                            label: 'Ending work access',
                            person: outgoing!,
                            icon: Icons.person_outline,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Icon(Icons.arrow_downward_rounded),
                          ),
                        ],
                        _PersonSummary(
                          label: 'New ${_roleName(widget.role)}',
                          person: selected!,
                          icon: _roleIcon(widget.role),
                          highlighted: true,
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: busy || needsRefresh
                                ? null
                                : () => setState(() {
                                    selected = null;
                                    reconciled = false;
                                  }),
                            child: const Text('Choose another person'),
                          ),
                        ),
                        const Text(
                          'Household links and past records stay unchanged. The new staff member keeps their own login.',
                        ),
                        if (!hasHousehold(selected!)) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Link the replacement to their own household first.',
                          ),
                          StaffHouseholdSetupButton(person: selected!),
                        ],
                        if (outgoing != null && !hasHousehold(outgoing!)) ...[
                          const SizedBox(height: 16),
                          Text(
                            '${_name(outgoing!)} has no household. Link one to retain personal access, or disable their login after reviewing the handover.',
                          ),
                          StaffHouseholdSetupButton(person: outgoing!),
                          TextButton(
                            onPressed: busy || !reconciled
                                ? null
                                : disableOutgoing,
                            child: const Text('Disable outgoing login'),
                          ),
                        ],
                        if (!householdsReady)
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => load(choose: selected!['id'] as String),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh household links'),
                          ),

                        if (widget.role == 'meter_reader') ...[
                          const SizedBox(height: 12),
                          const Text(
                            'The new Meter Reader pays their electricity bill normally. Monthly compensation is recorded by Cashier.',
                          ),
                        ],
                        const SizedBox(height: 20),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: reconciled,
                          onChanged: busy || needsRefresh
                              ? null
                              : (v) => setState(() => reconciled = v ?? false),
                          title: const Text('Ready for handover'),
                          subtitle: const Text(
                            'All affected phones are synced, pending work is reviewed, and any cash handover is complete.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed:
                              busy ||
                                  !reconciled ||
                                  needsRefresh ||
                                  !householdsReady
                              ? null
                              : save,
                          icon: const Icon(Icons.check),
                          label: Text(busy ? 'Saving…' : 'Confirm assignment'),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _PersonSummary extends StatelessWidget {
  const _PersonSummary({
    required this.label,
    required this.person,
    required this.icon,
    this.highlighted = false,
  });
  final String label;
  final AccountRow person;
  final IconData icon;
  final bool highlighted;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: highlighted
            ? Color.alphaBlend(
                colors.primary.withValues(alpha: 0.10),
                colors.surfaceContainerLowest,
              )
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: highlighted ? colors.primary : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelLarge),
                const SizedBox(height: 6),
                Text(_name(person), style: theme.textTheme.titleLarge),
                Text('@${person['username']}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMessage extends StatelessWidget {
  const _InlineMessage({required this.text, this.isError = false});
  final String text;
  final bool isError;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? colors.errorContainer : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? colors.onErrorContainer : colors.onSurface,
        ),
      ),
    );
  }
}
