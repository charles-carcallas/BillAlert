import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/staff_account.dart';
import '../common/failure_banner.dart';
import '../common/final_confirmation_dialog.dart';
import '../common/staff_app_bar.dart';
import 'account_form_widgets.dart';
import 'new_staff_controller.dart';

/// FR-31 — Admin › New Staff Account, adapted from Figma 70:1436.
///
/// The design's Admin option and area selector are deliberately absent: an
/// Area President may create only a Meter Reader or Cashier, and the server
/// always assigns the caller's own area. The temporary password is handed to
/// the staff member in person because BillAlert does not have an SMS sender.
class AdminNewStaffScreen extends ConsumerStatefulWidget {
  final bool embedded;
  final bool showIntro;

  const AdminNewStaffScreen({
    this.embedded = false,
    this.showIntro = true,
    super.key,
  });

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
      final Widget content = _CreatedStaff(
        account: created,
        onCreateAnother: () {
          _clearFields();
          controller.createAnother();
        },
        onDone: widget.embedded
            ? () {
                _clearFields();
                controller.createAnother();
              }
            : () => Navigator.of(context).maybePop(),
      );
      if (widget.embedded) return content;
      return Scaffold(
        appBar: const StaffAppBar(title: 'Staff account created'),
        body: content,
      );
    }

    final Widget content = SafeArea(
      child: AdminAccountFormLayout(
        children: <Widget>[
          if (widget.showIntro) ...<Widget>[
            Text(
              'Create a Meter Reader or Cashier account for your service '
              'area. Existing accounts remain unchanged.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
          ],
          if (state.failure != null) ...<Widget>[
            FailureBanner(failure: state.failure!),
            const SizedBox(height: 20),
          ],
          const AccountFormSectionTitle('Staff details'),
          const SizedBox(height: 14),
          AccountFormField(
            label: 'First name',
            child: TextField(
              controller: _firstName,
              enabled: !state.isSubmitting,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.givenName],
              decoration: const InputDecoration(hintText: 'Given name'),
            ),
          ),
          const SizedBox(height: 16),
          AccountFormField(
            label: 'Last name',
            child: TextField(
              controller: _lastName,
              enabled: !state.isSubmitting,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.familyName],
              decoration: const InputDecoration(hintText: 'Surname'),
            ),
          ),
          const SizedBox(height: 16),
          AccountFormField(
            label: 'Mobile number (optional)',
            child: TextField(
              controller: _contactNumber,
              enabled: !state.isSubmitting,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.telephoneNumber],
              decoration: const InputDecoration(hintText: 'e.g. 0917 555 0142'),
            ),
          ),
          const SizedBox(height: 18),
          AccountFormField(
            label: 'Role',
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<StaffRole>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  minimumSize: const WidgetStatePropertyAll<Size>(
                    Size.fromHeight(42),
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) =>
                        states.contains(WidgetState.selected)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerLowest,
                  ),
                  foregroundColor: WidgetStateProperty.resolveWith<Color?>(
                    (Set<WidgetState> states) =>
                        states.contains(WidgetState.selected)
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  side: WidgetStatePropertyAll<BorderSide>(
                    BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  shape: WidgetStatePropertyAll<OutlinedBorder>(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                segments: StaffRole.values
                    .map(
                      (StaffRole role) => ButtonSegment<StaffRole>(
                        value: role,
                        label: Text(role.label),
                      ),
                    )
                    .toList(),
                selected: <StaffRole>{_role},
                onSelectionChanged: state.isSubmitting
                    ? null
                    : (Set<StaffRole> roles) =>
                          setState(() => _role = roles.single),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const AccountFormNote(
            icon: Icons.location_on_outlined,
            title: 'Your service area',
            message:
                'The account is assigned to your Admin area automatically. '
                'The server also verifies that the role can be assigned.',
          ),
          const SizedBox(height: 24),
          const AccountFormSectionTitle('Sign-in details'),
          const SizedBox(height: 14),
          AccountFormField(
            label: 'Username',
            child: TextField(
              controller: _username,
              enabled: !state.isSubmitting,
              autocorrect: false,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.newUsername],
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
              ],
              decoration: const InputDecoration(
                hintText: 'e.g. rodrigo.balistoy',
              ),
            ),
          ),
          const SizedBox(height: 16),
          AccountFormField(
            label: 'Temporary password',
            child: TextField(
              controller: _temporaryPassword,
              enabled: !state.isSubmitting,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.newPassword],
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
          ),
          const SizedBox(height: 16),
          AccountFormField(
            label: 'Confirm temporary password',
            child: TextField(
              controller: _confirmPassword,
              enabled: !state.isSubmitting,
              obscureText: _obscurePassword,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.newPassword],
              decoration: const InputDecoration(
                hintText: 'Type the temporary password again',
              ),
            ),
          ),
          const SizedBox(height: 16),
          const AccountFormNote(
            icon: Icons.lock_reset_outlined,
            title: 'Secure handoff',
            message:
                'Give the temporary password to the staff member privately. '
                'BillAlert requires them to replace it at first sign-in.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: state.isSubmitting ? null : _submit,
              child: state.isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create staff account'),
            ),
          ),
        ],
      ),
    );

    if (widget.embedded) return content;
    return Scaffold(
      appBar: const StaffAppBar(title: 'New account'),
      body: content,
    );
  }

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
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
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
      ),
    );
  }
}
