import 'package:flutter/material.dart';

/// Shared visual structure for the two Admin account-creation forms.
///
/// Figma designs these at 360 logical pixels with 16-pixel gutters. Capping
/// the content width preserves that readable form measure on tablets and web
/// without changing the edge-to-edge phone layout.
class AdminAccountFormLayout extends StatelessWidget {
  final List<Widget> children;
  final double maxWidth;

  const AdminAccountFormLayout({
    required this.children,
    this.maxWidth = 400,
    super.key,
  });

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: children,
      ),
    ),
  );
}

/// The account-type switch at the top of the Admin Accounts tab.
///
/// This mirrors Figma's compact two-part control while keeping both options
/// as real buttons with an explicit selected state for accessibility.
class AdminAccountTypeSelector extends StatelessWidget {
  final bool staffSelected;
  final ValueChanged<bool> onStaffSelected;

  const AdminAccountTypeSelector({
    required this.staffSelected,
    required this.onStaffSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      height: 48 * MediaQuery.textScalerOf(context).scale(13) / 13,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _AccountTypeButton(
              label: 'Staff account',
              selected: staffSelected,
              onTap: () => onStaffSelected(true),
            ),
          ),
          Expanded(
            child: _AccountTypeButton(
              label: 'Consumer account',
              selected: !staffSelected,
              onTap: () => onStaffSelected(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTypeButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AccountTypeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colours.surfaceContainerLowest : Colors.transparent,
        elevation: selected ? 1 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? colours.onSurface : colours.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AccountFormSectionTitle extends StatelessWidget {
  final String label;
  final IconData? icon;

  const AccountFormSectionTitle(this.label, {this.icon, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (icon == null) return Text(label, style: theme.textTheme.titleMedium);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 10),
        Flexible(
          flex: 3,
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
      ],
    );
  }
}

class AccountFormHint extends StatelessWidget {
  const AccountFormHint({required this.icon, required this.message, super.key});
  final IconData icon;
  final String message;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(message, style: Theme.of(context).textTheme.bodySmall),
      ),
    ],
  );
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
  final bool compact;

  const AccountFormNote({
    required this.icon,
    required this.title,
    required this.message,
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 0 : 16,
        vertical: compact ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: compact
            ? Colors.transparent
            : colours.primary.withValues(alpha: 0.06),
        border: compact ? null : Border.all(color: colours.outlineVariant),
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
