import 'package:flutter/material.dart';

/// One read-only fact shown before an irreversible action is committed.
final class ConfirmationDetail {
  final String label;
  final String value;

  const ConfirmationDetail(this.label, this.value);
}

/// A consistent final checkpoint for BillAlert's irreversible mutations.
///
/// Validation still belongs to each controller/use case. This component only
/// repeats the real values the person is about to commit and returns whether
/// they chose to proceed.
Future<bool> showFinalConfirmation(
  BuildContext context, {
  required String title,
  required String subject,
  required List<ConfirmationDetail> details,
  required String warning,
  required String confirmLabel,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  subject,
                  style: Theme.of(dialogContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                for (final ConfirmationDetail detail in details) ...<Widget>[
                  _DetailRow(detail: detail),
                  const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                Text(
                  warning,
                  style: Theme.of(dialogContext).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Review'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ) ??
      false;
}

class _DetailRow extends StatelessWidget {
  final ConfirmationDetail detail;

  const _DetailRow({required this.detail});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(child: Text(detail.label)),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          detail.value,
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: TextAlign.end,
        ),
      ),
    ],
  );
}
