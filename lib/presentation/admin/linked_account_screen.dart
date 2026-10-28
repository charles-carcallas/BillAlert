import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/account_management_repository.dart';
import '../../domain/entities/app_user.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import 'account_management_providers.dart';
import 'temporary_password_card.dart';

class LinkedAccountCreated {
  const LinkedAccountCreated(this.id, this.username, this.password);
  final String id, username, password;
}

/// One submission creates the login, profile and verified household link.
/// Candidates stay consumers until the separate reviewed appointment succeeds.
class LinkedAccountScreen extends ConsumerStatefulWidget {
  const LinkedAccountScreen({
    super.key,
    this.candidate = false,
    this.successor = false,
    this.household,
    this.householdMode = 'existing',
  });
  final bool candidate, successor;
  final AccountRow? household;
  final String householdMode;
  @override
  ConsumerState<LinkedAccountScreen> createState() => _LinkedAccountState();
}

class _LinkedAccountState extends ConsumerState<LinkedAccountScreen> {
  final form = GlobalKey<FormState>();
  final first = TextEditingController(),
      last = TextEditingController(),
      username = TextEditingController(),
      number = TextEditingController(),
      meter = TextEditingController(),
      purok = TextEditingController(),
      contact = TextEditingController(),
      reference = TextEditingController(),
      opening = TextEditingController();
  String role = 'consumer', mode = 'new';
  AccountRow? household;
  List<AccountRow> available = [];
  bool loading = true,
      busy = false,
      confirmed = false,
      reconciled = false,
      attempted = false,
      usernameEdited = false;
  String? error;
  late final String? actorScope;
  late final String password;
  LinkedAccountCreated? created;

  @override
  void initState() {
    super.initState();
    actorScope = ref.read(authControllerProvider).value?.accessScope;
    password = ref.read(temporaryPasswordFactoryProvider)();
    household = widget.household;
    if (household != null) {
      mode = widget.householdMode;
      if (mode != 'handover') {
        first.text = '${household!['first_name']}';
        last.text = '${household!['last_name']}';
        suggest();
      }
    }
    load();
  }

  Future<void> load() async {
    try {
      final data = await ref
          .read(accountManagementRepositoryProvider)
          .workspace();
      available = AccountManagementRepository.rows(data['households'])
          .where(
            (h) => h['account_status'] == 'active' && h['profile_id'] == null,
          )
          .toList();
    } catch (_) {
      error = 'Connect to load households before creating an account.';
    }
    if (mounted) setState(() => loading = false);
  }

  void suggest() {
    if (!usernameEdited) {
      username.text = '${first.text.trim()}.${last.text.trim()}'
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    }
  }

  @override
  void dispose() {
    for (final c in [
      first,
      last,
      username,
      number,
      meter,
      purok,
      contact,
      reference,
      opening,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || attempted || !form.currentState!.validate()) return;
    if (!confirmed ||
        (widget.successor && !reconciled) ||
        (mode != 'new' && household == null)) {
      setState(() => error = 'Choose their household and confirm the details.');
      return;
    }
    final actor = ref.read(authControllerProvider).value;
    if (actor is! AdminUser || actor.accessScope != actorScope) {
      setState(() => error = 'Your work access changed. Reopen Accounts.');
      return;
    }
    if (!ref.read(networkStatusProvider).isOnline) {
      setState(() => error = 'Connect before creating an account.');
      return;
    }
    setState(() {
      busy = true;
      attempted = true;
      error = null;
    });
    try {
      final id = await ref
          .read(accountManagementRepositoryProvider)
          .createLinkedAccount({
            'action': widget.successor ? 'create_successor' : 'create_account',
            'role': role,
            'username': username.text.trim(),
            'first_name': first.text.trim(),
            'last_name': last.text.trim(),
            'temporary_password': password,
            'reconciled': reconciled,
            'reason': reference.text.trim().isEmpty
                ? 'Own household verified during account setup'
                : reference.text.trim(),
            'household': {
              'mode': mode,
              'confirmed': true,
              'id': household?['id'],
              'consumer_no': number.text.trim(),
              'meter': meter.text.trim(),
              'purok': purok.text.trim(),
              'contact': contact.text.trim(),
              'reference': reference.text.trim(),
              'opening_reading': opening.text.trim(),
            },
          });
      if (!mounted) return;
      if (ref.read(authControllerProvider).value?.accessScope != actorScope) {
        throw const AccountManagementException(
          'Your work access changed. Ask the Area President to check the new account.',
        );
      }
      ref.invalidate(accountWorkspaceProvider);
      setState(
        () =>
            created = LinkedAccountCreated(id, username.text.trim(), password),
      );
    } on AccountManagementException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          attempted = !e.safeToRetry;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = AccountManagementRepository.uncertain);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(
    TextEditingController c,
    String label, {
    bool required = true,
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      enabled: !attempted,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) {
        if (c == first || c == last) suggest();
      },
      validator: (v) =>
          required && (v == null || v.trim().isEmpty) ? 'Enter $label' : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.successor ? 'Nominate a successor' : 'New account',
          ),
        ),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      if (created != null) ...[
                        Icon(
                          Icons.check_circle_outline,
                          size: 48,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Account and household ready',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.candidate
                              ? 'Continue to review the staff appointment. Their household is already linked.'
                              : widget.successor
                              ? 'The successor must sign in, change the temporary password and accept the transfer.'
                              : 'Share these details privately. They will choose their own password at first sign-in.',
                        ),
                        const SizedBox(height: 24),
                        TemporaryPasswordCard(
                          username: created!.username,
                          temporaryPassword: created!.password,
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, created),
                          child: Text(
                            widget.candidate ? 'Continue to review' : 'Done',
                          ),
                        ),
                      ] else
                        Form(
                          key: form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (busy) const LinearProgressIndicator(),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Text(
                                    error!,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              Text('Person', style: theme.textTheme.titleLarge),
                              const SizedBox(height: 16),
                              field(first, 'First name'),
                              field(last, 'Last name'),
                              if (!widget.candidate && !widget.successor) ...[
                                Text(
                                  'Role',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                SegmentedButton<String>(
                                  expandedInsets: EdgeInsets.zero,
                                  showSelectedIcon: false,
                                  segments: const [
                                    ButtonSegment(
                                      value: 'consumer',
                                      label: Text(
                                        'Consumer',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'meter_reader',
                                      label: Text(
                                        'Meter Reader',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    ButtonSegment(
                                      value: 'cashier',
                                      label: Text(
                                        'Cashier',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                  selected: {role},
                                  onSelectionChanged: attempted
                                      ? null
                                      : (values) => setState(
                                          () => role = values.single,
                                        ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Already has a login? Assign their position in Manage accounts → Staff.',
                                ),
                              ],
                              const SizedBox(height: 24),
                              Text(
                                'Their household',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              if (widget.household == null) ...[
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final entry in {
                                      'new': 'New household',
                                      'existing': 'Existing',
                                    }.entries)
                                      ChoiceChip(
                                        label: Text(entry.value),
                                        selected: mode == entry.key,
                                        onSelected: attempted
                                            ? null
                                            : (_) => setState(() {
                                                mode = entry.key;
                                                confirmed = false;
                                              }),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (mode == 'existing' &&
                                  widget.household == null) ...[
                                DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: household?['id'] as String?,
                                  decoration: const InputDecoration(
                                    labelText: 'Unlinked household',
                                  ),
                                  items: [
                                    for (final h in available)
                                      DropdownMenuItem(
                                        value: h['id'] as String,
                                        child: Text(
                                          '${h['consumer_no']} · ${h['first_name']} ${h['last_name']}',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: attempted
                                      ? null
                                      : (id) => setState(() {
                                          household = available.firstWhere(
                                            (h) => h['id'] == id,
                                          );
                                          confirmed = false;
                                        }),
                                  validator: (v) =>
                                      v == null ? 'Select a household' : null,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Households that already have a login use that existing account. Do not create a duplicate.',
                                ),
                              ],
                              if (widget.household != null)
                                Text(
                                  '${household!['consumer_no']} · ${household!['first_name']} ${household!['last_name']}',
                                ),
                              if (mode == 'new' || mode == 'handover') ...[
                                field(number, 'Consumer number'),
                                if (mode == 'new') ...[
                                  field(
                                    meter,
                                    'Meter number (optional)',
                                    required: false,
                                  ),
                                  field(
                                    purok,
                                    'Purok (optional)',
                                    required: false,
                                  ),
                                ],
                                field(
                                  contact,
                                  'SMS number (optional)',
                                  required: false,
                                ),
                              ],
                              if (mode == 'handover') ...[
                                const Text(
                                  'A new household keeps the previous occupant’s bills and history separate. Post the closing reading first.',
                                ),
                                field(
                                  opening,
                                  'Opening meter reading',
                                  numeric: true,
                                ),
                              ],
                              if (mode == 'same_household')
                                const Text(
                                  'Disable the previous login first. This replaces access to the same household and its history.',
                                ),
                              if (widget.successor ||
                                  mode == 'handover' ||
                                  mode == 'same_household')
                                field(reference, 'Review reference / reason'),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: confirmed,
                                onChanged: attempted
                                    ? null
                                    : (v) => setState(
                                        () => confirmed = v ?? false,
                                      ),
                                title: const Text(
                                  'This is their own household',
                                ),
                                subtitle: const Text(
                                  'This login will be able to view its bills and history.',
                                ),
                              ),
                              if (widget.successor)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: reconciled,
                                  onChanged: attempted
                                      ? null
                                      : (v) => setState(
                                          () => reconciled = v ?? false,
                                        ),
                                  title: const Text(
                                    'Pending work and handover reviewed',
                                  ),
                                ),
                              const SizedBox(height: 24),
                              Text(
                                'Sign-in details',
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: username,
                                enabled: !attempted,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Username',
                                ),
                                onChanged: (_) => usernameEdited = true,
                                validator: (v) =>
                                    RegExp(
                                      r'^[a-z][a-z0-9._-]{2,49}$',
                                    ).hasMatch(v?.trim() ?? '')
                                    ? null
                                    : 'Use 3–50 lowercase letters, numbers, dots or underscores; start with a letter.',
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'A temporary password is generated automatically.',
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: attempted || busy ? null : save,
                                icon: const Icon(
                                  Icons.person_add_alt_1_outlined,
                                ),
                                label: Text(
                                  busy
                                      ? 'Creating…'
                                      : error == null
                                      ? 'Create account'
                                      : 'Retry setup',
                                ),
                              ),
                              if (attempted && !busy)
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Back to check accounts'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
