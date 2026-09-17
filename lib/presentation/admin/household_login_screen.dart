import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/entities/household_login.dart';
import '../common/failure_banner.dart';
import '../common/final_confirmation_dialog.dart';
import '../common/local_sort_button.dart';
import 'account_form_widgets.dart';
import 'household_login_controller.dart';
import 'temporary_password_card.dart';

/// MTR-04 — Admin › Accounts › Give a household a sign-in.
///
/// New Consumer gives a new household its sign-in in the same step. This
/// screen is for the rest: households added before that, and a sign-in that
/// could not be created then — most often because the username was taken.
/// The Area President chooses the household, confirms a username, and hands
/// over the temporary password BillAlert makes. GEN-04
/// then makes the household replace it at first sign-in, so the Area
/// President never knows the password that stays.
///
/// Two steps on one screen, like resetting a password. Opened from New
/// Consumer with the household just created, it skips straight to the second
/// and closes with `true` once the sign-in exists.
class AdminHouseholdLoginScreen extends ConsumerStatefulWidget {
  /// The household to give a sign-in, when the caller already knows which.
  final HouseholdWithoutLogin? household;

  const AdminHouseholdLoginScreen({this.household, super.key});

  @override
  ConsumerState<AdminHouseholdLoginScreen> createState() =>
      _AdminHouseholdLoginScreenState();
}

class _AdminHouseholdLoginScreenState
    extends ConsumerState<AdminHouseholdLoginScreen> {
  final TextEditingController _username = TextEditingController();

  HouseholdWithoutLogin? _selected;
  String _query = '';
  LocalNameSort _sort = LocalNameSort.az;

  /// Opened for one household, so there is no list to go back to.
  bool get _openedForOne => widget.household != null;

  @override
  void initState() {
    super.initState();
    final HouseholdWithoutLogin? household = widget.household;
    if (household != null) {
      _selected = household;
      _username.text = household.suggestedUsername;
    }
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AdminHouseholdLoginState state = ref.watch(
      adminHouseholdLoginControllerProvider,
    );
    final CreatedHouseholdLogin? done = state.created;
    final HouseholdWithoutLogin? selected = _selected;

    if (done != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Sign-in created')),
        body: _LoginCreated(
          login: done,
          onAnother: _openedForOne ? null : _giveAnother,
          onDone: () => Navigator.of(context).maybePop(true),
        ),
      );
    }

    return PopScope(
      // On the form, back returns to the list instead of leaving.
      canPop: selected == null || _openedForOne,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _backToList();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            selected == null
                ? 'Give a household a sign-in'
                : 'Create a sign-in',
          ),
          leading: selected == null || _openedForOne
              ? null
              : IconButton(
                  tooltip: 'Back to households',
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
    final households = ref.watch(householdsWithoutLoginProvider);

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
                    'Choose the household that should be able to sign in. '
                    'Only active households in your service area without a '
                    'sign-in are listed.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          onChanged: (String value) =>
                              setState(() => _query = value),
                          decoration: const InputDecoration(
                            hintText: 'Search by name or consumer number',
                            prefixIcon: Icon(Icons.search),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: LocalSortButton<LocalNameSort>(
                          buttonKey: const ValueKey('household-login-sort'),
                          value: _sort,
                          options: localNameSortOptions,
                          onChanged: (value) => setState(() => _sort = value),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: households.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (Object error, StackTrace _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: FailureBanner(
                    failure: error is AppFailure
                        ? error
                        : ServerFailure(ServerFailure.defaultMessage, '$error'),
                    onRetry: () =>
                        ref.invalidate(householdsWithoutLoginProvider),
                  ),
                ),
                data: _householdList,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _householdList(List<HouseholdWithoutLogin> all) {
    if (all.isEmpty) {
      return const _Empty(
        title: 'Every household can sign in',
        message:
            'All active households in your service area already have a '
            'sign-in.',
      );
    }

    final List<HouseholdWithoutLogin> visible =
        all.where((HouseholdWithoutLogin h) => h.matches(_query)).toList()
          ..sort((a, b) => compareNames(a.fullName, b.fullName, _sort));
    if (visible.isEmpty) {
      return const _Empty(
        title: 'No matching households',
        message: 'Try a different name or consumer number.',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: <Widget>[
        for (final HouseholdWithoutLogin household in visible)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.home_outlined),
              title: Text(household.fullName),
              subtitle: Text(_referenceOf(household)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _choose(household),
            ),
          ),
      ],
    );
  }

  Widget _form(
    BuildContext context,
    HouseholdWithoutLogin household,
    AdminHouseholdLoginState state,
  ) => AdminAccountFormLayout(
    children: <Widget>[
      _HouseholdHeader(household: household),
      const SizedBox(height: 20),
      if (state.failure != null) ...<Widget>[
        FailureBanner(failure: state.failure!),
        const SizedBox(height: 20),
      ],
      const AccountFormSectionTitle('Sign-in details'),
      const SizedBox(height: 14),
      AccountFormField(
        label: 'Username',
        child: TextField(
          controller: _username,
          enabled: !state.isSubmitting,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.newUsername],
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
          ],
          decoration: const InputDecoration(hintText: 'e.g. lorna.caberte'),
        ),
      ),
      const SizedBox(height: 16),
      AccountFormNote(
        icon: Icons.password_outlined,
        title: 'Temporary password',
        message:
            'BillAlert makes one, like BillAlert4829, and shows it once after '
            'the sign-in is created. ${household.firstName} must choose their '
            'own at first sign-in.',
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 52,
        child: FilledButton(
          onPressed: state.isSubmitting ? null : () => _submit(household),
          child: state.isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create sign-in'),
        ),
      ),
    ],
  );

  void _choose(HouseholdWithoutLogin household) {
    ref.read(adminHouseholdLoginControllerProvider.notifier).clear();
    _username.text = household.suggestedUsername;
    setState(() => _selected = household);
  }

  void _backToList() {
    _username.clear();
    ref.read(adminHouseholdLoginControllerProvider.notifier).clear();
    setState(() => _selected = null);
  }

  /// After a sign-in was created: the household just served has left the
  /// list, so it is read again.
  void _giveAnother() {
    _backToList();
    ref.invalidate(householdsWithoutLoginProvider);
  }

  Future<void> _submit(HouseholdWithoutLogin household) async {
    final AdminHouseholdLoginController controller = ref.read(
      adminHouseholdLoginControllerProvider.notifier,
    );
    final String username = _username.text.trim().toLowerCase();

    // A malformed username goes straight to the use case's own message,
    // without a confirmation for a sign-in that could not be created.
    if (!RegExp(r'^[a-z][a-z0-9._-]{2,49}$').hasMatch(username)) {
      await _create(controller, household);
      return;
    }

    final bool confirmed = await showFinalConfirmation(
      context,
      title: 'Create this sign-in?',
      subject: household.fullName,
      details: <ConfirmationDetail>[
        ConfirmationDetail('Consumer number', household.consumerNo.value),
        ConfirmationDetail('Username', username),
      ],
      warning:
          'This household will be able to sign in to BillAlert and see its '
          'own bills, receipts and notices. A temporary password is made and '
          'shown on the next screen.',
      confirmLabel: 'Create sign-in',
    );

    if (!mounted || !confirmed) return;
    await _create(controller, household);
  }

  Future<void> _create(
    AdminHouseholdLoginController controller,
    HouseholdWithoutLogin household,
  ) => controller.create(household: household, username: _username.text);
}

/// "2026-1204-TUB · Purok 3", or just the number when there is no purok.
String _referenceOf(HouseholdWithoutLogin household) {
  final String? purok = household.purok;
  return purok == null || purok.isEmpty
      ? household.consumerNo.value
      : '${household.consumerNo.value} · $purok';
}

class _HouseholdHeader extends StatelessWidget {
  final HouseholdWithoutLogin household;

  const _HouseholdHeader({required this.household});

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
            child: Icon(Icons.home_outlined, color: colours.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  household.fullName,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(_referenceOf(household), style: text.bodySmall),
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
              Icons.how_to_reg_outlined,
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

class _LoginCreated extends StatelessWidget {
  final CreatedHouseholdLogin login;

  /// Null when the screen was opened for one household.
  final VoidCallback? onAnother;
  final VoidCallback onDone;

  const _LoginCreated({
    required this.login,
    required this.onAnother,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final VoidCallback? onAnother = this.onAnother;

    // Scrolls, rather than pushing the buttons down with a Spacer: a long
    // name wraps the title, and a small phone then has less height than this
    // needs.
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
                Icon(Icons.check_circle, size: 64, color: colours.primary),
                const SizedBox(height: 16),
                Text(
                  'Sign-in created for ${login.household.fullName}',
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  _referenceOf(login.household),
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TemporaryPasswordCard(
                  username: login.username,
                  temporaryPassword: login.temporaryPassword,
                ),
                const SizedBox(height: 16),
                Text(
                  'Give these to ${login.household.firstName} in person or '
                  'send them from your phone. The password is not shown '
                  'again, and BillAlert will ask for a new one at first '
                  'sign-in.',
                  style: text.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                if (onAnother != null) ...<Widget>[
                  OutlinedButton(
                    onPressed: onAnother,
                    child: const Text('Give another household a sign-in'),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(onPressed: onDone, child: const Text('Done')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
