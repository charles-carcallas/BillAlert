import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'account_management_providers.dart';

class ReconciliationWarning extends ConsumerWidget {
  const ReconciliationWarning({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(accountPendingWorkProvider);
    return Text(
      '${pending.when(data: (count) => '$count unsynced or rejected items '
          'for this session on this phone.', loading: () => 'Checking this phone’s queue…', error: (_, _) => 'This phone’s queue could not be checked.')} '
      'Other phones and quarantined work are not counted. Review readings, '
      'payments, notices and remittance on all affected phones before ending work. '
      'A zero count does not confirm reconciliation.',
    );
  }
}

/// Compact reviewed form. The checkbox is always an explicit human assertion.
Future<Map<String, String>?> accountForm(
  BuildContext context, {
  required String title,
  required Map<String, String> fields,
  String? explanation,
  bool reconciliation = false,
  Map<String, Map<String, String>> choices = const {},
  Map<String, String> initialValues = const {},
  Set<String> optionalFields = const {},
  String confirmLabel = 'Confirm',
}) => showDialog<Map<String, String>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _AccountForm(
    title: title,
    fields: fields,
    explanation: explanation,
    reconciliation: reconciliation,
    choices: choices,
    initialValues: initialValues,
    optionalFields: optionalFields,
    confirmLabel: confirmLabel,
  ),
);

class _AccountForm extends StatefulWidget {
  const _AccountForm({
    required this.title,
    required this.fields,
    required this.explanation,
    required this.reconciliation,
    required this.choices,
    required this.initialValues,
    required this.optionalFields,
    required this.confirmLabel,
  });
  final String title;
  final Map<String, String> fields;
  final String? explanation;
  final bool reconciliation;
  final Map<String, Map<String, String>> choices;
  final Map<String, String> initialValues;
  final Set<String> optionalFields;
  final String confirmLabel;
  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final key = GlobalKey<FormState>();
  late final controllers = {
    for (final name in widget.fields.keys)
      name: TextEditingController(text: widget.initialValues[name]),
  };
  late final selected = <String, String>{
    for (final name in widget.choices.keys)
      if (widget.choices[name]!.containsKey(widget.initialValues[name]))
        name: widget.initialValues[name]!,
  };
  bool reconciled = false;
  bool submitted = false;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.explanation != null) Text(widget.explanation!),
              for (final field in widget.fields.entries)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: widget.choices.containsKey(field.key)
                      ? DropdownButtonFormField<String>(
                          initialValue: selected[field.key],
                          isExpanded: true,
                          decoration: InputDecoration(labelText: field.value),
                          items: widget.choices[field.key]!.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => selected[field.key] = v ?? '',
                          validator: (v) => v == null || v.isEmpty
                              ? 'Choose an account.'
                              : null,
                        )
                      : TextFormField(
                          controller: controllers[field.key],
                          obscureText: field.key == 'temporary_password',
                          autocorrect: field.key != 'temporary_password',
                          decoration: InputDecoration(labelText: field.value),
                          validator: (v) {
                            if (widget.optionalFields.contains(field.key) &&
                                (v == null || v.trim().isEmpty)) {
                              return null;
                            }
                            if (v == null || v.trim().isEmpty) {
                              return 'Required.';
                            }
                            if (field.key == 'opening_reading') {
                              final n = num.tryParse(v);
                              if (n == null || !n.isFinite || n < 0) {
                                return 'Enter a non-negative reading.';
                              }
                            }
                            if (field.key == 'temporary_password' &&
                                v.length < 8) {
                              return 'Use at least 8 characters.';
                            }
                            if (field.key == 'username' &&
                                !RegExp(
                                  r'^[a-z][a-z0-9._-]{2,49}$',
                                ).hasMatch(v.trim().toLowerCase())) {
                              return 'Use 3–50 characters; start with a letter.';
                            }
                            return null;
                          },
                        ),
                ),
              if (widget.reconciliation) ...[
                const SizedBox(height: 16),
                const ReconciliationWarning(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: reconciled,
                  onChanged: (v) => setState(() => reconciled = v ?? false),
                  title: const Text(
                    'I have reviewed pending work on all affected phones, cash and remittance, and reconciled the handover.',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: submitted || (widget.reconciliation && !reconciled)
            ? null
            : () {
                if (submitted) return;
                if (key.currentState!.validate()) {
                  setState(() => submitted = true);
                  Navigator.pop(context, {
                    for (final e in controllers.entries)
                      e.key: e.key == 'temporary_password'
                          ? e.value.text
                          : e.value.text.trim(),
                    ...selected,
                    'reconciled': '$reconciled',
                  });
                }
              },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
