import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// `Consumer` here means a household, not Riverpod's widget.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/entities/household_login.dart';
import '../../domain/usecases/admin/create_consumer.dart';
import '../../domain/usecases/admin/create_household_login.dart';
import '../../domain/usecases/admin/register_household.dart';
import '../common/failure_banner.dart';
import '../common/final_confirmation_dialog.dart';
import '../common/staff_app_bar.dart';
import '../router.dart';
import 'account_form_widgets.dart';
import 'new_consumer_controller.dart';
import 'temporary_password_card.dart';

/// ADM-03 + MTR-04 — Admin › New Consumer, based on Figma 70:6009.
///
/// The design omitted consumer_no even though the database requires it and
/// has no generator. Functionality wins: the Area President supplies the
/// number printed on the household record. Area and creator are taken from
/// the signed-in Admin; barangay is deployment-wide settings data. The meter
/// number is optional, because a household can be registered before its
/// meter is commissioned.
///
/// Creating the household also gives it its sign-in: a username suggested
/// from the name, and a temporary password BillAlert makes and shows once.
class AdminNewConsumerScreen extends ConsumerStatefulWidget {
  final bool embedded;
  final bool showIntro;

  const AdminNewConsumerScreen({
    this.embedded = false,
    this.showIntro = true,
    super.key,
  });

  @override
  ConsumerState<AdminNewConsumerScreen> createState() =>
      _AdminNewConsumerScreenState();
}

class _AdminNewConsumerScreenState
    extends ConsumerState<AdminNewConsumerScreen> {
  final TextEditingController _consumerNo = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _contactNumber = TextEditingController();
  final TextEditingController _purok = TextEditingController();
  final TextEditingController _meterSerialNo = TextEditingController();
  final TextEditingController _username = TextEditingController();

  /// Once the Area President types a username themselves, the name no longer
  /// rewrites it.
  bool _usernameEdited = false;

  @override
  void dispose() {
    _consumerNo.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _contactNumber.dispose();
    _purok.dispose();
    _meterSerialNo.dispose();
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AdminNewConsumerState state = ref.watch(
      adminNewConsumerControllerProvider,
    );
    final AdminNewConsumerController controller = ref.read(
      adminNewConsumerControllerProvider.notifier,
    );

    final RegisteredHousehold? registered = state.registered;
    if (registered != null) {
      // Done on the confirmation, and also the way back once a sign-in that
      // failed here has been created: embedded in Accounts it starts a fresh
      // form, opened on its own it closes.
      void finish() {
        if (widget.embedded) {
          _clearFields();
          controller.createAnother();
        } else {
          Navigator.of(context).maybePop();
        }
      }

      final Consumer created = registered.household;
      final Widget content = _Registered(
        registered: registered,
        onCreateLogin: () async {
          final bool? loginCreated = await context.push<bool>(
            Routes.householdLogin,
            extra: HouseholdWithoutLogin(
              id: created.id,
              consumerNo: created.consumerNo,
              firstName: created.firstName,
              lastName: created.lastName,
              purok: created.purok,
            ),
          );
          if (loginCreated == true && mounted) finish();
        },
        onCreateAnother: () {
          _clearFields();
          controller.createAnother();
        },
        onDone: finish,
      );
      if (widget.embedded) return content;
      return Scaffold(
        appBar: const StaffAppBar(title: 'Consumer created'),
        body: content,
      );
    }

    final Widget content = SafeArea(
      child: AdminAccountFormLayout(
        children: <Widget>[
          if (widget.showIntro) ...<Widget>[
            Text(
              'Add a household to your service area. Existing accounts '
              'remain available from the Accounts tab.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
          ],
          if (state.failure != null) ...<Widget>[
            FailureBanner(failure: state.failure!),
            const SizedBox(height: 20),
          ],
          const AccountFormSectionTitle('Household details'),
          const SizedBox(height: 14),
          AccountFormField(
            label: 'Consumer number',
            child: TextField(
              controller: _consumerNo,
              enabled: !state.isSubmitting,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: const InputDecoration(hintText: 'e.g. 2026-1234-TUB'),
            ),
          ),
          const SizedBox(height: 16),
          AccountFormField(
            label: 'First name',
            child: TextField(
              controller: _firstName,
              enabled: !state.isSubmitting,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const <String>[AutofillHints.givenName],
              onChanged: (_) => _suggestUsername(),
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
              onChanged: (_) => _suggestUsername(),
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
          const SizedBox(height: 16),
          AccountFormField(
            label: 'Purok (optional)',
            child: TextField(
              controller: _purok,
              enabled: !state.isSubmitting,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'e.g. Purok 3'),
            ),
          ),
          const SizedBox(height: 16),
          AccountFormField(
            label: 'Meter number (optional)',
            child: TextField(
              controller: _meterSerialNo,
              enabled: !state.isSubmitting,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: const InputDecoration(hintText: 'e.g. BIEC-08317'),
            ),
          ),
          const SizedBox(height: 16),
          const AccountFormNote(
            icon: Icons.home_work_outlined,
            title: 'Assigned automatically',
            message:
                'Barangay Tubod and your service area come from your Admin '
                'account. Leave the meter number blank if the meter is not '
                'installed yet.',
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
              textInputAction: TextInputAction.done,
              autofillHints: const <String>[AutofillHints.newUsername],
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
              ],
              onChanged: (_) => _usernameEdited = true,
              decoration: const InputDecoration(hintText: 'e.g. lorna.caberte'),
            ),
          ),
          const SizedBox(height: 16),
          const AccountFormNote(
            icon: Icons.password_outlined,
            title: 'Temporary password',
            message:
                'BillAlert makes one, like BillAlert4829, and shows it once '
                'after the household is created. The household must choose '
                'its own at first sign-in.',
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: state.isSubmitting ? null : _submit,
              child: state.isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create consumer account'),
            ),
          ),
          const SizedBox(height: 8),
          // MTR-04: households added before sign-ins were created here, and a
          // sign-in that could not be created at the time, are finished from
          // here. Below the form, so the household fields keep their place.
          TextButton.icon(
            onPressed: state.isSubmitting
                ? null
                : () => context.push(Routes.householdLogin),
            icon: const Icon(Icons.how_to_reg_outlined, size: 18),
            label: const Text('Give an existing household a sign-in'),
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

  void _suggestUsername() {
    if (_usernameEdited) return;
    _username.text = HouseholdWithoutLogin.usernameFor(
      _firstName.text,
      _lastName.text,
    );
  }

  Future<void> _submit() async {
    final AdminNewConsumerController controller = ref.read(
      adminNewConsumerControllerProvider.notifier,
    );

    // Obvious mistakes go straight to the use case's own messages, without a
    // confirmation for a household that could not be created.
    if (CreateConsumer.check(
              consumerNo: _consumerNo.text,
              firstName: _firstName.text,
              lastName: _lastName.text,
            ) !=
            null ||
        CreateHouseholdLogin.checkUsername(_username.text) != null) {
      await _create(controller);
      return;
    }

    final bool confirmed = await showFinalConfirmation(
      context,
      title: 'Confirm new consumer',
      subject: '${_firstName.text.trim()} ${_lastName.text.trim()}',
      details: <ConfirmationDetail>[
        ConfirmationDetail('Consumer number', _consumerNo.text.trim()),
        ConfirmationDetail(
          'Mobile number',
          _optionalValue(_contactNumber.text),
        ),
        ConfirmationDetail('Purok', _optionalValue(_purok.text)),
        ConfirmationDetail(
          'Meter number',
          _optionalValue(_meterSerialNo.text.toUpperCase()),
        ),
        ConfirmationDetail('Username', _username.text.trim().toLowerCase()),
        const ConfirmationDetail('Service area', 'Your assigned area'),
      ],
      warning:
          'This creates a permanent household record and its sign-in. '
          'BillAlert has no consumer deletion action, so review the number '
          'and name carefully. A temporary password is made and shown on the '
          'next screen.',
      confirmLabel: 'Create consumer',
    );

    if (!mounted || !confirmed) return;
    await _create(controller);
  }

  Future<void> _create(AdminNewConsumerController controller) =>
      controller.create(
        consumerNo: _consumerNo.text,
        firstName: _firstName.text,
        lastName: _lastName.text,
        contactNumber: _contactNumber.text,
        purok: _purok.text,
        meterSerialNo: _meterSerialNo.text,
        username: _username.text,
      );

  static String _optionalValue(String value) =>
      value.trim().isEmpty ? 'Not provided' : value.trim();

  void _clearFields() {
    _consumerNo.clear();
    _firstName.clear();
    _lastName.clear();
    _contactNumber.clear();
    _purok.clear();
    _meterSerialNo.clear();
    _username.clear();
    _usernameEdited = false;
  }
}

class _Registered extends StatelessWidget {
  final RegisteredHousehold registered;

  /// Only offered when the sign-in could not be created with the household.
  final VoidCallback onCreateLogin;
  final VoidCallback onCreateAnother;
  final VoidCallback onDone;

  const _Registered({
    required this.registered,
    required this.onCreateLogin,
    required this.onCreateAnother,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Consumer consumer = registered.household;
    final CreatedHouseholdLogin? login = registered.login;
    final String? meterSerialNo = consumer.meterSerialNo;

    // Scrolls, rather than pushing the buttons down with a Spacer: embedded in
    // Accounts, under its header and above the tab bar, a small phone has
    // less height than the password card needs.
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
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  consumer.fullName,
                  style: text.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  meterSerialNo == null
                      ? consumer.consumerNo.value
                      : '${consumer.consumerNo.value} · Meter $meterSerialNo',
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (login != null) ...<Widget>[
                  TemporaryPasswordCard(
                    username: login.username,
                    temporaryPassword: login.temporaryPassword,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'The household and its sign-in are ready. Give these to '
                    '${consumer.firstName} in person or send them from your '
                    'phone. The password is not shown again, and BillAlert '
                    'will ask for a new one at first sign-in.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ] else ...<Widget>[
                  FailureBanner(
                    failure: registered.loginFailure ?? const ServerFailure(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The household is saved, but its sign-in was not created, '
                    'so ${consumer.firstName} cannot use BillAlert yet.',
                    style: text.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: onCreateLogin,
                    icon: const Icon(Icons.how_to_reg_outlined, size: 18),
                    label: const Text('Create the sign-in'),
                  ),
                ],
                const SizedBox(height: 32),
                OutlinedButton(
                  onPressed: onCreateAnother,
                  child: const Text('Create another'),
                ),
                const SizedBox(height: 8),
                if (login != null)
                  FilledButton(onPressed: onDone, child: const Text('Done'))
                else
                  TextButton(onPressed: onDone, child: const Text('Done')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
