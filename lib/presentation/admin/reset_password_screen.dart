import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/entities/managed_account.dart';
import '../../domain/usecases/admin/reset_account_password.dart';
import '../common/failure_banner.dart';
import '../common/final_confirmation_dialog.dart';
import 'account_form_widgets.dart';
import 'reset_password_controller.dart';

/// Admin › Accounts › Reset a forgotten password.
///
/// "Forgot password?" on the sign-in screen sends people to their Area
/// President. This is what the Area President does next: choose the account,
/// set a temporary password, and hand it over in person. GEN-04 then makes the
/// person replace it at their next sign-in, so the Area President never knows
/// the password that stays.
///
/// Two steps on one screen, like serving a notice: find the account, then set
/// the password. The password step ends in a final confirmation, because the
/// person's current password stops working the moment it is confirmed.
class AdminResetPasswordScreen extends ConsumerStatefulWidget {
  const AdminResetPasswordScreen({super.key});

  @override
  ConsumerState<AdminResetPasswordScreen> createState() =>
      _AdminResetPasswordScreenState();
}

class _AdminResetPasswordScreenState
    extends ConsumerState<AdminResetPasswordScreen> {
  final TextEditingController _temporary = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  ManagedAccount? _selected;
  String _query = '';
  bool _obscure = true;

  @override
  void dispose() {
    _temporary.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AdminResetPasswordState state = ref.watch(
      adminResetPasswordControllerProvider,
    );
    final ManagedAccount? done = state.resetFor;
    final ManagedAccount? selected = _selected;

    if (done != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Password reset')),
        body: _ResetDone(
          account: done,
          onResetAnother: _backToList,
          onDone: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    return PopScope(
      // On the password step, back returns to the list instead of leaving.
      canPop: selected == null,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _backToList();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            selected == null ? 'Reset a password' : 'Set a temporary password',
          ),
          leading: selected == null
              ? null
              : IconButton(
                  tooltip: 'Back to accounts',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _backToList,
                ),
        ),
        body: SafeArea(
          child: selected == null
              ? _picker(context)
              : _form(context, selected, state),
        ),
      ),
    );
  }

  Widget _picker(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final accounts = ref.watch(managedAccountsProvider);

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Choose the account whose password was forgotten. Only '
                    'accounts in your service area are listed.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (String value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      hintText: 'Search by name, username or consumer number',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: accounts.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: FailureBanner(
                    failure: error is AppFailure
                        ? error
                        : ServerFailure(ServerFailure.defaultMessage, '$error'),
                    onRetry: () => ref.invalidate(managedAccountsProvider),
                  ),
                ),
                data: (List<ManagedAccount> all) => _accountList(all),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountList(List<ManagedAccount> all) {
    if (all.isEmpty) {
      return const _Empty(
        title: 'No accounts to reset',
        message: 'Nobody in your service area has a sign-in yet.',
      );
    }

    final List<ManagedAccount> visible = all
        .where((ManagedAccount a) => a.matches(_query))
        .toList();
    if (visible.isEmpty) {
      return const _Empty(
        title: 'No matching accounts',
        message: 'Try a different name, username or consumer number.',
      );
    }

    final List<ManagedAccount> staff = visible
        .where((ManagedAccount a) => a.kind != ManagedAccountKind.consumer)
        .toList();
    final List<ManagedAccount> households = visible
        .where((ManagedAccount a) => a.kind == ManagedAccountKind.consumer)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: <Widget>[
        if (staff.isNotEmpty) ...<Widget>[
          const AccountFormSectionTitle('Staff'),
          const SizedBox(height: 8),
          for (final ManagedAccount account in staff)
            _AccountTile(account: account, onTap: () => _choose(account)),
        ],
        if (households.isNotEmpty) ...<Widget>[
          if (staff.isNotEmpty) const SizedBox(height: 16),
          const AccountFormSectionTitle('Households'),
          const SizedBox(height: 8),
          for (final ManagedAccount account in households)
            _AccountTile(account: account, onTap: () => _choose(account)),
        ],
      ],
    );
  }

  Widget _form(
    BuildContext context,
    ManagedAccount account,
    AdminResetPasswordState state,
  ) => AdminAccountFormLayout(
    children: <Widget>[
      _AccountHeader(account: account),
      const SizedBox(height: 20),
      if (state.failure != null) ...<Widget>[
        FailureBanner(failure: state.failure!),
        const SizedBox(height: 20),
      ],
      AccountFormField(
        label: 'Temporary password',
        child: TextField(
          controller: _temporary,
          enabled: !state.isSubmitting,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText:
                'At least ${ResetAccountPassword.minimumLength} characters',
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              onPressed: state.isSubmitting
                  ? null
                  : () => setState(() => _obscure = !_obscure),
              icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      AccountFormField(
        label: 'Confirm temporary password',
        child: TextField(
          controller: _confirm,
          enabled: !state.isSubmitting,
          obscureText: _obscure,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Type the temporary password again',
          ),
        ),
      ),
      const SizedBox(height: 16),
      AccountFormNote(
        icon: Icons.lock_reset_outlined,
        title: 'Secure handoff',
        message:
            'Give the temporary password to ${account.firstName} in person. '
            'BillAlert will ask them to choose a new one when they sign in.',
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: state.isSubmitting ? null : () => _submit(account),
          child: state.isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Reset password'),
        ),
      ),
    ],
  );

  void _choose(ManagedAccount account) {
    ref.read(adminResetPasswordControllerProvider.notifier).clear();
    setState(() => _selected = account);
  }

  void _backToList() {
    _temporary.clear();
    _confirm.clear();
    ref.read(adminResetPasswordControllerProvider.notifier).clear();
    setState(() {
      _selected = null;
      _obscure = true;
    });
  }

  Future<void> _submit(ManagedAccount account) async {
    final AdminResetPasswordController controller = ref.read(
      adminResetPasswordControllerProvider.notifier,
    );

    // Obvious mistakes go straight to the use case's own messages, without a
    // confirmation for a reset that could not happen.
    if (_temporary.text.length < ResetAccountPassword.minimumLength ||
        _temporary.text != _confirm.text) {
      await _reset(controller, account);
      return;
    }

    final bool confirmed = await showFinalConfirmation(
      context,
      title: 'Reset this password?',
      subject: account.fullName,
      details: <ConfirmationDetail>[
        ConfirmationDetail('Account', account.kind.label),
        ConfirmationDetail(
          account.kind == ManagedAccountKind.consumer
              ? 'Consumer number'
              : 'Username',
          account.reference,
        ),
      ],
      warning:
          'Their current password stops working as soon as you confirm, and '
          'they must choose a new one the next time they sign in. The '
          'temporary password is not shown here; hand it over in person.',
      confirmLabel: 'Reset password',
    );

    if (!mounted || !confirmed) return;
    await _reset(controller, account);
  }

  Future<void> _reset(
    AdminResetPasswordController controller,
    ManagedAccount account,
  ) => controller.reset(
    account: account,
    temporaryPassword: _temporary.text,
    confirmPassword: _confirm.text,
  );
}

IconData _iconFor(ManagedAccountKind kind) => switch (kind) {
  ManagedAccountKind.meterReader => Icons.speed_outlined,
  ManagedAccountKind.cashier => Icons.point_of_sale_outlined,
  ManagedAccountKind.consumer => Icons.home_outlined,
};

class _AccountTile extends StatelessWidget {
  final ManagedAccount account;
  final VoidCallback onTap;

  const _AccountTile({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: Icon(_iconFor(account.kind)),
      title: Text(account.fullName),
      subtitle: Text('${account.kind.label} · ${account.reference}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _AccountHeader extends StatelessWidget {
  final ManagedAccount account;

  const _AccountHeader({required this.account});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colours.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconFor(account.kind), color: colours.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  account.fullName,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${account.kind.label} · ${account.reference}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String title;
  final String message;

  const _Empty({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.manage_accounts_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(title, style: text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ResetDone extends StatelessWidget {
  final ManagedAccount account;
  final VoidCallback onResetAnother;
  final VoidCallback onDone;

  const _ResetDone({
    required this.account,
    required this.onResetAnother,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
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
                  'Temporary password set for ${account.fullName}',
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${account.kind.label} · ${account.reference}',
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Give them the temporary password in person. BillAlert '
                  'will ask them to choose a new password when they sign in.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: onResetAnother,
                  child: const Text('Reset another'),
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
