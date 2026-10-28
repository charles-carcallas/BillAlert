import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../data/repositories/account_management_repository.dart';
import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';
import '../auth/linked_household_provider.dart';
import '../consumer/current_bill_controller.dart';
import 'account_management_forms.dart';
import 'account_management_providers.dart';
import 'new_consumer_controller.dart';

/// The person is fixed before selecting a household: no second login picker.
class StaffHouseholdSetupButton extends ConsumerStatefulWidget {
  const StaffHouseholdSetupButton({
    super.key,
    required this.person,
    this.label = 'Set up household',
  });
  final AccountRow person;
  final String label;
  @override
  ConsumerState<StaffHouseholdSetupButton> createState() => _SetupState();
}

class _SetupState extends ConsumerState<StaffHouseholdSetupButton> {
  bool busy = false;
  String? message;
  Future<void> setup() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final actor = await ref.read(authControllerProvider.future);
      if (!mounted) return;
      if (actor is! AdminUser || actor.areaId == null) return;
      // Fetch fresh membership, rather than trusting the screen's old list.
      final repository = ref.read(accountManagementRepositoryProvider);
      final data = await repository.workspace();
      final households = AccountManagementRepository.rows(data['households']);
      if (!mounted) return;
      if (households.any((h) => h['profile_id'] == widget.person['id'])) {
        setState(() => message = 'This account already has a household.');
        return;
      }
      final available = households
          .where(
            (h) => h['account_status'] == 'active' && h['profile_id'] == null,
          )
          .toList();
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Household for ${widget.person['first_name']}'),
          content: const Text(
            'Choose their existing electricity account to keep its readings and bills, or create a new household record. No additional login is needed.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(context, 'existing'),
              child: const Text('Choose existing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'new'),
              child: const Text('Create new'),
            ),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      String? householdId;
      if (choice == 'existing') {
        householdId = await showDialog<String>(
          context: context,
          builder: (_) => _HouseholdPicker(rows: available),
        );
        if (!mounted || householdId == null) return;
        final h = available.firstWhere((h) => h['id'] == householdId);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm household owner'),
            content: Text(
              'Link ${h['consumer_no']} — ${h['first_name']} ${h['last_name']} to ${widget.person['first_name']} ${widget.person['last_name']}? Confirm this is their own household. Existing bills and history will be visible to this login.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Link household'),
              ),
            ],
          ),
        );
        if (!mounted || confirmed != true) return;
      } else {
        final form = await accountForm(
          context,
          title: 'Create and link household',
          explanation:
              'Use the consumer number assigned to this household. For an existing meter with earlier readings, choose its existing record instead. New records start at zero until a reading is recorded.',
          fields: const {
            'consumer_no': 'Consumer number',
            'first_name': 'First name',
            'last_name': 'Last name',
            'meter': 'Meter number (optional)',
            'purok': 'Purok (optional)',
            'contact': 'SMS number (optional)',
          },
          initialValues: {
            'first_name': '${widget.person['first_name']}',
            'last_name': '${widget.person['last_name']}',
          },
          optionalFields: const {'meter', 'purok', 'contact'},
          confirmLabel: 'Create and link',
        );
        if (!mounted || form == null) return;
        final result = await ref.read(createConsumerUseCaseProvider)(
          consumerNo: form['consumer_no']!,
          firstName: form['first_name']!,
          lastName: form['last_name']!,
          contactNumber: form['contact']!,
          purok: form['purok']!,
          meterSerialNo: form['meter']!,
          areaId: actor.areaId!,
          createdBy: actor.id,
        );
        if (!mounted) return;
        switch (result) {
          case Err(:final failure):
            setState(
              () => message =
                  '${failure.message} Refresh the household list before repeating creation.',
            );
            return;
          case Ok(:final value):
            householdId = value.id.value;
        }
      }
      try {
        await repository.link(
          householdId,
          widget.person['id'] as String,
          widget.person['role'] == 'consumer' ? 'same_household' : 'staff_link',
          'Own household confirmed during guided setup',
        );
      } catch (_) {
        if (mounted) {
          setState(
            () => message =
                'The household link could not be confirmed. Refresh first. If the record exists without a login, choose it under “Choose existing”; do not create it again.',
          );
        }
        return;
      }
      await ref.read(authControllerProvider.notifier).confirmSession();
      if (mounted) {
        ref.invalidate(linkedHouseholdProvider);
        ref.invalidate(currentBillControllerProvider);
        setState(
          () => message = 'Household linked. Open My household to view it.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => message =
              'Could not load household setup. Connect and try again.',
        );
      }
    } finally {
      if (mounted) {
        ref.invalidate(accountWorkspaceProvider);
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : setup,
          icon: const Icon(Icons.home_outlined),
          label: Text(widget.label),
        ),
        if (message != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(message!)),
      ],
    );
  }
}

class _HouseholdPicker extends StatefulWidget {
  const _HouseholdPicker({required this.rows});
  final List<AccountRow> rows;
  @override
  State<_HouseholdPicker> createState() => _PickerState();
}

class _PickerState extends State<_HouseholdPicker> {
  String search = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Choose existing household'),
    content: SizedBox(
      width: 440,
      height: 320,
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Search name, consumer or meter number',
            ),
            onChanged: (value) =>
                setState(() => search = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 12),
          if (widget.rows.isEmpty)
            const Text(
              'No unlinked households are available. Cancel and choose Create new. Households linked to someone else require a reviewed handover.',
            ),
          Expanded(
            child: ListView(
              children: [
                for (final h in widget.rows.where(
                  (h) =>
                      '${h['consumer_no']} ${h['first_name']} ${h['last_name']} ${h['meter_serial_no'] ?? ''}'
                          .toLowerCase()
                          .contains(search),
                ))
                  ListTile(
                    title: Text('${h['first_name']} ${h['last_name']}'),
                    subtitle: Text(
                      '${h['consumer_no']} · Meter ${h['meter_serial_no'] ?? 'not set'}',
                    ),
                    onTap: () => Navigator.pop(context, h['id'] as String),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
