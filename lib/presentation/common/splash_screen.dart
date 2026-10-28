import 'package:flutter/material.dart';

import 'billalert_logo.dart';

/// Shown for the moment it takes to find out whether a session was saved.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const BillAlertLogo(size: 88),
                const SizedBox(height: 20),
                Text(
                  'BillAlert',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: 112,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(8),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    semanticsLabel: 'Opening BillAlert',
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Opening BillAlert…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
