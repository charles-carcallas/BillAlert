import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/staff_account.dart';
import '../common/failure_banner.dart';
import '../common/final_confirmation_dialog.dart';
import 'new_staff_controller.dart';

/// FR-31 — Admin › New Staff Account, adapted from Figma 70:1436.
///
/// The design's Admin option and area selector are deliberately absent: an
/// Area President may create only a Meter Reader or Cashier, and the server
/// always assigns the caller's own area. The temporary password is handed to
/// the staff member in person because BillAlert does not have an SMS sender.
class AdminNewStaffScreen extends ConsumerStatefulWidget {
  const AdminNewStaffScreen({super.key});

  @override
  ConsumerState<AdminNewStaffScreen> createState() =>
      _AdminNewStaffScreenState();
}

class _AdminNewStaffScreenState extends ConsumerState<AdminNewStaffScreen> {
  final _username = TextEditingController();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _contactNumber = TextEditingController();
  final _temporaryPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  StaffRole _role = StaffRole.meterReader;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _username.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _contactNumber.dispose();
    _temporaryPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminNewStaffControllerProvider);
    final controller = ref.read(adminNewStaffControllerProvider.notifier);
    final created = state.created;

    if (created != null) {
      return _CreatedStaff(
        account: created,
        onCreateAnother: () {
          _clearFields();
          controller.createAnother();
        },
        onDone: () => Navigator.of(context).maybePop(),
      );
    }

    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New staff account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Create a Meter Reader or Cashier account. It is '
                      'assigned to your service area automatically.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            if (state.failure != null) ...<Widget>[
              const SizedBox(height: 12),
              FailureBanner(failure: state.failure!),
            ],
            const SizedBox(height: 22),
            Text(
              'STAFF DETAILS',
              style: text.labelMedium?.copyWith(letterSpacing: 0.6),
            ),
            const SizedBox(height: 12),
            _label('First name', text),
            TextField(
              controller: _firstName,
              enabled: !state.isSubmitting,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Given name'),
            ),
            const SizedBox(height: 16),
            _label('Last name', text),
            TextField(
              controller: _lastName,
              enabled: !state.isSubmitting,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Surname'),
            ),
            const SizedBox(height: 16),
            _label('Mobile number (optional)', text),
            TextField(
              controller: _contactNumber,
              enabled: !state.isSubmitting,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'e.g. 0917 555 0142'),
            ),
            const SizedBox(height: 18),
            _label('Role', text),
            SegmentedButton<StaffRole>(
              segments: StaffRole.values
                  .map(
                    (role) => ButtonSegment<StaffRole>(
                      value: role,
                      label: Text(role.label),
                      icon: Icon(
                        role == StaffRole.meterReader
                            ? Icons.speed_outlined
                            : Icons.point_of_sale_outlined,
                      ),
                    ),
                  )
                  .toList(),
              selected: <StaffRole>{_role},
              onSelectionChanged: state.isSubmitting
                  ? null
                  : (roles) => setState(() => _role = roles.single),
            ),
            const SizedBox(height: 24),
            Text(
              'SIGN-IN DETAILS',
              style: text.labelMedium?.copyWith(letterSpacing: 0.6),
            ),
            const SizedBox(height: 12),
            _label('Username', text),
            TextField(
              controller: _username,
              enabled: !state.isSubmitting,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
              ],
              decoration: const InputDecoration(
                hintText: 'e.g. rodrigo.balistoy',
              ),
            ),
            const SizedBox(height: 16),
            _label('Temporary password', text),
            TextField(
              controller: _temporaryPassword,
              enabled: !state.isSubmitting,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: 'At least 8 characters',
                suffixIcon: IconButton(
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  onPressed: state.isSubmitting
                      ? null
                      : () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _label('Confirm temporary password', text),
            TextField(
              controller: _confirmPassword,
              enabled: !state.isSubmitting,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                hintText: 'Type the temporary password again',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.lock_reset_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Give the temporary password to the new staff member '
                      'securely. They must replace it at first sign-in.',
                      style: text.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: state.isSubmitting ? null : _submit,
              child: state.isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create staff account'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String value, TextTheme text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(value, style: text.titleSmall),
  );

  Future<void> _submit() async {
    final AdminNewStaffController controller = ref.read(
      adminNewStaffControllerProvider.notifier,
    );
    final String username = _username.text.trim().toLowerCase();

    // Obvious invalid input goes directly to the existing validation path.
    if (!RegExp(r'^[a-z][a-z0-9._-]{2,49}$').hasMatch(username) ||
        _firstName.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty ||
        _temporaryPassword.text.length < 8 ||
        _temporaryPassword.text != _confirmPassword.text) {
      await _create(controller);
      return;
    }

    final bool confirmed = await showFinalConfirmation(
      context,
      title: 'Confirm new staff account',
      subject: '${_firstName.text.trim()} ${_lastName.text.trim()}',
      details: <ConfirmationDetail>[
        ConfirmationDetail('Username', username),
        ConfirmationDetail('Role', _role.label),
        ConfirmationDetail(
          'Mobile number',
          _contactNumber.text.trim().isEmpty
              ? 'Not provided'
              : _contactNumber.text.trim(),
        ),
        const ConfirmationDetail('Service area', 'Your assigned area'),
      ],
      warning:
          'This creates a permanent sign-in and staff profile. The temporary '
          'password is deliberately not displayed here; hand it over securely.',
      confirmLabel: 'Create staff account',
    );

    if (!mounted || !confirmed) return;
    await _create(controller);
  }

  Future<void> _create(AdminNewStaffController controller) => controller.create(
    username: _username.text,
    firstName: _firstName.text,
    lastName: _lastName.text,
    contactNumber: _contactNumber.text,
    role: _role,
    temporaryPassword: _temporaryPassword.text,
    confirmPassword: _confirmPassword.text,
  );

  void _clearFields() {
    _username.clear();
    _firstName.clear();
    _lastName.clear();
    _contactNumber.clear();
    _temporaryPassword.clear();
    _confirmPassword.clear();
    setState(() {
      _role = StaffRole.meterReader;
      _obscurePassword = true;
    });
  }
}

class _CreatedStaff extends StatelessWidget {
  final CreatedStaffAccount account;
  final VoidCallback onCreateAnother;
  final VoidCallback onDone;

  const _CreatedStaff({
    required this.account,
    required this.onCreateAnother,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Staff account created')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 24),
              Icon(
                Icons.check_circle,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                account.fullName,
                style: text.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '${account.role.label} · ${account.username}',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'The account is active in your service area. Give the '
                'temporary password to this staff member securely; the app '
                'will require a new password at first sign-in.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: onCreateAnother,
                child: const Text('Create another'),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}
