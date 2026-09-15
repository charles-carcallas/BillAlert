import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The sign-in details an Area President hands over, shown once.
///
/// BillAlert has no SMS sender, so these reach the person in person — which
/// is what the large type is for — or from the Area President's own phone,
/// which is what Copy is for.
class TemporaryPasswordCard extends StatelessWidget {
  /// Null when the Area President cannot see it: a household's username is
  /// not readable by staff.
  final String? username;
  final String temporaryPassword;

  const TemporaryPasswordCard({
    required this.temporaryPassword,
    this.username,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final String? username = this.username;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (username != null) ...<Widget>[
            _Detail(label: 'Username', value: username),
            const SizedBox(height: 12),
          ],
          _Detail(label: 'Temporary password', value: temporaryPassword),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _copy(context),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Copy'),
          ),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final String? username = this.username;
    await Clipboard.setData(
      ClipboardData(
        text: username == null
            ? 'Temporary password: $temporaryPassword'
            : 'Username: $username\nTemporary password: $temporaryPassword',
      ),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied. Paste it into a message to send.')),
    );
  }
}

class _Detail extends StatelessWidget {
  final String label;
  final String value;

  const _Detail({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      children: <Widget>[
        Text(label, style: text.bodySmall),
        const SizedBox(height: 4),
        SelectableText(
          value,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
