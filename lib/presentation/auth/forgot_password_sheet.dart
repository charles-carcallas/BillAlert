import 'package:flutter/material.dart';

/// "Forgot password?" on the sign-in screen.
///
/// There is no reset link to send. A username signs in with a synthetic
/// address — "ledesman.dormal@billalert.local" — and no inbox exists behind
/// it, so an emailed link would go nowhere. Nobody self-registers either:
/// Phase 1 has every account issued by an Admin. So getting back in follows
/// the same path as a new account — a temporary password, replaced at the
/// next sign-in (GEN-04) — and this sheet says exactly that, rather than
/// offering a form that could not deliver.
Future<void> showForgotPasswordHelp(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const ForgotPasswordHelp(),
    );

class ForgotPasswordHelp extends StatelessWidget {
  const ForgotPasswordHelp({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Center(
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colours.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_reset, size: 30, color: colours.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Forgot your password?',
            textAlign: TextAlign.center,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Your Area President can arrange a new one for you.',
            textAlign: TextAlign.center,
            style: text.bodyMedium,
          ),
          const SizedBox(height: 22),
          const _Step(
            number: 1,
            title: 'Ask your Area President for a temporary password',
            note: 'They manage the BillAlert accounts in your service area.',
          ),
          const _Step(
            number: 2,
            title: 'Sign in with it, using your usual username',
            note: 'Type the temporary password exactly as you were given it.',
          ),
          const _Step(
            number: 3,
            title: 'Choose a new password when BillAlert asks',
            note: 'The temporary password stops working once you do.',
            isLast: true,
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colours.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: colours.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "BillAlert can't email you a reset link. Your username "
                    "isn't connected to an email inbox.",
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to sign in'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String title;
  final String note;
  final bool isLast;

  const _Step({
    required this.number,
    required this.title,
    required this.note,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colours.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: text.labelLarge?.copyWith(
                color: colours.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(note, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
