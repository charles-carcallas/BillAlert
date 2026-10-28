import 'package:flutter/material.dart';

import '../../data/repositories/account_management_repository.dart';
import '../common/expandable_bottom_sheet.dart';
import 'staff_household_setup.dart';

String _role(AccountRow person) => switch (person['role']) {
  'admin' => 'Area President',
  'meter_reader' => 'Meter Reader',
  'cashier' => 'Cashier',
  _ => 'Consumer',
};

String _name(AccountRow person) =>
    '${person['first_name']} ${person['last_name']}';

String? _status(AccountRow person) {
  if (person['account_status'] == 'inactive') return 'Login disabled';
  if (person['account_status'] != 'active') return 'Pending activation';
  if (person['role'] != 'consumer' && person['staff_enabled'] != true) {
    return 'Work access ended / pending';
  }
  return null;
}

/// Scan names first; open one person's details for infrequent account actions.
class AccountPeopleList extends StatelessWidget {
  const AccountPeopleList({
    required this.people,
    required this.households,
    required this.currentUserId,
    required this.onAction,
    super.key,
  });

  final List<AccountRow> people;
  final List<AccountRow> households;
  final String currentUserId;
  final void Function(AccountRow person, String action) onAction;

  Future<void> _open(BuildContext context, AccountRow person) async {
    AccountRow? household;
    for (final row in households) {
      if (row['profile_id'] == person['id']) {
        household = row;
        break;
      }
    }
    final action = await showExpandableBottomSheet<String>(
      context: context,
      initialSize: 0.65,
      builder: (context, controller) => _PersonDetails(
        person: person,
        household: household,
        scrollController: controller,
        isYou: person['id'] == currentUserId,
      ),
    );
    if (context.mounted && action != null) onAction(person, action);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < people.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 72,
                endIndent: 16,
                color: colors.outlineVariant,
              ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: _Avatar(person: people[i]),
              title: Text(
                '${_name(people[i])}${people[i]['id'] == currentUserId ? ' (You)' : ''}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                [_role(people[i]), ?_status(people[i])].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: () => _open(context, people[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.person});
  final AccountRow person;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initials = [person['first_name'], person['last_name']]
        .map((name) => '$name'.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => name.characters.first.toUpperCase())
        .join();
    return CircleAvatar(
      radius: 20,
      backgroundColor: colors.primary.withValues(alpha: 0.10),
      foregroundColor: colors.primary,
      child: Text(
        initials,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PersonDetails extends StatelessWidget {
  const _PersonDetails({
    required this.person,
    required this.household,
    required this.scrollController,
    required this.isYou,
  });
  final AccountRow person;
  final AccountRow? household;
  final ScrollController scrollController;
  final bool isYou;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _status(person);
    final isAdmin = person['role'] == 'admin';
    final staff = person['role'] != 'consumer';
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      children: [
        Row(
          children: [
            _Avatar(person: person),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_name(person), style: theme.textTheme.titleLarge),
                  Text(
                    '@${person['username']}',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close account details',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${_role(person)}${isYou ? ' · Your account' : ''}',
          style: theme.textTheme.titleSmall,
        ),
        if (status != null) ...[
          const SizedBox(height: 6),
          Text(status, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 24),
        Text('Household', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (household != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.home_outlined),
            title: Text('${household!['consumer_no'] ?? 'Linked household'}'),
            subtitle: household!['first_name'] == null
                ? null
                : Text(_name(household!)),
          )
        else ...[
          const Text('No household linked.'),
          if (person['account_status'] == 'active') ...[
            const SizedBox(height: 12),
            StaffHouseholdSetupButton(
              person: person,
              label: isYou ? 'Set up my household' : 'Set up household',
            ),
          ],
        ],
        if (!isAdmin) ...[
          const SizedBox(height: 24),
          Text('Account actions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (staff)
            _Action(
              icon: Icons.work_outline,
              label: person['staff_enabled'] == true
                  ? 'End work access'
                  : 'Restore work access',
              action: person['staff_enabled'] == true
                  ? 'end_work'
                  : 'restore_work',
            ),
          _Action(
            icon: person['account_status'] == 'active'
                ? Icons.lock_outline
                : Icons.lock_open_outlined,
            label: person['account_status'] == 'active'
                ? 'Disable login'
                : 'Enable login',
            action: person['account_status'] == 'active'
                ? 'disable_login'
                : 'enable_login',
          ),
        ],
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.action,
  });
  final IconData icon;
  final String label, action;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right_rounded, size: 20),
    onTap: () => Navigator.pop(context, action),
  );
}
