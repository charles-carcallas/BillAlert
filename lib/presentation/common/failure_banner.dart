import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';

/// Shows a failure to the user.
///
/// It renders `failure.message` and nothing else. `failure.debugDetail` holds
/// the Postgres code or the exception text, and it deliberately does not
/// appear here: a consumer reading "PostgrestException(code: 23505)" learns
/// nothing and loses confidence in the app.
///
/// A NetworkFailure is drawn in a calm colour rather than an alarming one.
/// For a meter reader in Tubod, having no signal is the normal state of
/// affairs and their work is already saved.
class FailureBanner extends StatelessWidget {
  final AppFailure failure;
  final VoidCallback? onRetry;

  const FailureBanner({required this.failure, this.onRetry, super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isReassuring = failure is NetworkFailure;

    final Color background =
        isReassuring ? scheme.secondaryContainer : scheme.errorContainer;
    final Color foreground =
        isReassuring ? scheme.onSecondaryContainer : scheme.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isReassuring ? Icons.cloud_off : Icons.error_outline,
            color: foreground,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failure.message,
              style: TextStyle(color: foreground),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
        ],
      ),
    );
  }
}
