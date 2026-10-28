import 'package:flutter/material.dart';

const double desktopBreakpoint = 900;

/// Two columns when cards have enough room to remain readable.
class ResponsiveCards extends StatelessWidget {
  final List<Widget> children;
  const ResponsiveCards({required this.children, super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 920 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

class DesktopSignInLayout extends StatelessWidget {
  final Widget child;
  const DesktopSignInLayout({required this.child, super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= desktopBreakpoint;
      final colors = Theme.of(context).colorScheme;
      return Row(
        children: [
          if (desktop)
            Expanded(
              child: ColoredBox(
                color: colors.primaryContainer,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(48),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.electric_bolt,
                            size: 56,
                            color: colors.onPrimaryContainer,
                          ),
                          const SizedBox(height: 28),
                          Text(
                            'Your community.\nYour bills, together.',
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(color: colors.onPrimaryContainer),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Readings, billing and payment records for Barangay Tubod.',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: colors.onPrimaryContainer),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Expanded(child: Center(child: child)),
        ],
      );
    },
  );
}
