import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/entities/managed_account.dart';
import '../common/failure_banner.dart';
import '../common/final_confirmation_dialog.dart';
import 'account_form_widgets.dart';
import 'reset_password_controller.dart';
import 'temporary_password_card.dart';

/// Admin › Accounts › Reset a forgotten password.
///
/// "Forgot password?" on the sign-in screen sends people to their Area
/// President. This is what the Area President does next: choose the account,
/// confirm, and hand over the temporary password BillAlert makes. GEN-04 then
/// makes the person replace it at their next sign-in, so the Area President
/// never knows the password that stays.
///
/// Two steps on one screen, like serving a notice: find the account, then
/// reset it. The reset ends in a final confirmation, because the person's
/// current password stops working the moment it is confirmed.
class AdminResetPasswordScreen extends ConsumerStatefulWidget {
  const AdminResetPasswordScreen({super.key});

  @override
  ConsumerState<AdminResetPasswordScreen> createState() =>
      _AdminResetPasswordScreenState();
}

class _AdminResetPasswordScreenState
    extends ConsumerState<AdminResetPasswordScreen> {
  ManagedAccount? _selected;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final AdminResetPasswordState state = ref.watch(
      adminResetPasswordControllerProvider,
    );
    final ManagedAccount? done = state.resetFor;
    final String? temporaryPassword = state.temporaryPassword;
    final ManagedAccount? selected = _selected;

    if (done != null && temporaryPassword != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Password reset')),
        body: _ResetDone(
          account: done,
          temporaryPassword: temporaryPassword,
          onResetAnother: _backToList,
          onDone: () => Navigator.of(context).maybePop(),
        ),
      );
    }

    return PopScope(
      // On the reset step, back returns to the list instead of leaving.
      canPop: selected == null,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _backToList();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            selected == null ? 'Reset a password' : 'Reset this password',
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
      AccountFormNote(
        icon: Icons.password_outlined,
        title: 'A new temporary password',
        message:
            'BillAlert makes one, like BillAlert4829, and shows it once after '
            'the reset. ${account.firstName} must choose their own at the '
            'next sign-in.',
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
    ref.read(adminResetPasswordControllerProvider.notifier).clear();
    setState(() => _selected = null);
  }

  Future<void> _submit(ManagedAccount account) async {
    final AdminResetPasswordController controller = ref.read(
      adminResetPasswordControllerProvider.notifier,
    );

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
          'they must choose a new one the next time they sign in. A temporary '
          'password is made and shown on the next screen.',
      confirmLabel: 'Reset password',
    );

    if (!mounted || !confirmed) return;
    await controller.reset(account: account);
  }
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
  final String temporaryPassword;
  final VoidCallback onResetAnother;
  final VoidCallback onDone;

  const _ResetDone({
    required this.account,
    required this.temporaryPassword,
    required this.onResetAnother,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    // Scrolls, rather than pushing the buttons down with a Spacer, so the
    // password card fits on a small phone.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 352),
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
                  'New temporary password for ${account.fullName}',
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  '${account.kind.label} · ${account.reference}',
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                // A household's username is not readable by staff, so only
                // staff accounts show one. The reference above is theirs.
                TemporaryPasswordCard(
                  username: account.kind == ManagedAccountKind.consumer
                      ? null
                      : account.reference,
                  temporaryPassword: temporaryPassword,
                ),
                const SizedBox(height: 16),
                Text(
                  'Give it to ${account.firstName} in person or send it from '
                  'your phone. It is not shown again, and BillAlert will ask '
                  'them to choose a new password when they sign in.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
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
