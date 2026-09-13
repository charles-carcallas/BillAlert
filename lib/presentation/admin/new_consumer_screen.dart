import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// `Consumer` here means a household, not Riverpod's widget.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../domain/entities/consumer.dart';
import '../common/failure_banner.dart';
import '../common/final_confirmation_dialog.dart';
import '../common/staff_app_bar.dart';
import 'account_form_widgets.dart';
import 'new_consumer_controller.dart';

/// ADM-03 — Admin › New Consumer, based on Figma 70:6009.
///
/// The design omitted consumer_no even though the database requires it and
/// has no generator. Functionality wins: the Area President supplies the
/// number printed on the household record. Area and creator are taken from
/// the signed-in Admin; barangay is deployment-wide settings data.
class AdminNewConsumerScreen extends ConsumerStatefulWidget {
  const AdminNewConsumerScreen({super.key});

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

  @override
  void dispose() {
    _consumerNo.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _contactNumber.dispose();
    _purok.dispose();
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

    final Consumer? created = state.created;
    if (created != null) {
      return _CreatedConsumer(
        consumer: created,
        onCreateAnother: () {
          _clearFields();
          controller.createAnother();
        },
        onDone: () => Navigator.of(context).maybePop(),
      );
    }

    return Scaffold(
      appBar: const StaffAppBar(title: 'New account'),
      body: SafeArea(
        child: AdminAccountFormLayout(
          children: <Widget>[
            Text(
              'Add a household to your service area. Existing accounts '
              'remain available from the Accounts tab.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (state.failure != null) ...<Widget>[
              const SizedBox(height: 12),
              FailureBanner(failure: state.failure!),
            ],
            const SizedBox(height: 20),
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
                decoration: const InputDecoration(
                  hintText: 'e.g. 2026-1234-TUB',
                ),
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
                decoration: const InputDecoration(
                  hintText: 'e.g. 0917 555 0142',
                ),
              ),
            ),
            const SizedBox(height: 16),
            AccountFormField(
              label: 'Purok (optional)',
              child: TextField(
                controller: _purok,
                enabled: !state.isSubmitting,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(hintText: 'e.g. Purok 3'),
              ),
            ),
            const SizedBox(height: 16),
            const AccountFormNote(
              icon: Icons.home_work_outlined,
              title: 'Assigned automatically',
              message:
                  'Barangay Tubod and your service area come from your Admin '
                  'account. Meter details and sign-in access are added '
                  'separately.',
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
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final AdminNewConsumerController controller = ref.read(
      adminNewConsumerControllerProvider.notifier,
    );

    if (_consumerNo.text.trim().isEmpty ||
        _firstName.text.trim().isEmpty ||
        _lastName.text.trim().isEmpty) {
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
        const ConfirmationDetail('Service area', 'Your assigned area'),
      ],
      warning:
          'This creates a permanent household record. BillAlert has no '
          'consumer deletion action, so review the number and name carefully.',
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
      );

  static String _optionalValue(String value) =>
      value.trim().isEmpty ? 'Not provided' : value.trim();

  void _clearFields() {
    _consumerNo.clear();
    _firstName.clear();
    _lastName.clear();
    _contactNumber.clear();
    _purok.clear();
  }
}

class _CreatedConsumer extends StatelessWidget {
  final Consumer consumer;
  final VoidCallback onCreateAnother;
  final VoidCallback onDone;

  const _CreatedConsumer({
    required this.consumer,
    required this.onCreateAnother,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Consumer created')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
                consumer.consumerNo.value,
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'The household record is active in this service area. No '
                'sign-in account was created.',
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
