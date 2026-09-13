import 'package:flutter/material.dart';

/// Shared visual structure for the two Admin account-creation forms.
///
/// Figma designs these at 360 logical pixels with 16-pixel gutters. Capping
/// the content width preserves that readable form measure on tablets and web
/// without changing the edge-to-edge phone layout.
class AdminAccountFormLayout extends StatelessWidget {
  final List<Widget> children;

  const AdminAccountFormLayout({required this.children, super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: children,
      ),
    ),
  );
}

class AccountFormSectionTitle extends StatelessWidget {
  final String label;

  const AccountFormSectionTitle(this.label, {super.key});

  @override
  Widget build(BuildContext context) =>
      Text(label, style: Theme.of(context).textTheme.titleMedium);
}

class AccountFormField extends StatelessWidget {
  final String label;
  final Widget child;

  const AccountFormField({required this.label, required this.child, super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        label,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      child,
    ],
  );
}

/// Pale-green explanatory card used by the Figma account forms.
class AccountFormNote extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const AccountFormNote({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.06),
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: colours.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: text.titleSmall),
                const SizedBox(height: 3),
                Text(message, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
