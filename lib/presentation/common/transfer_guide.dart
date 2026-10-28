import 'package:flutter/material.dart';

class TransferGuide extends StatelessWidget {
  const TransferGuide({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.swap_horiz_rounded,
              color: theme.colorScheme.primary,
              size: 28,
            ),
            const SizedBox(height: 12),
            Text('Area President transfer', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Hand over the position while keeping each person’s household and past work under their own name.',
            ),
            const SizedBox(height: 24),
            for (final step in const [
              (
                '1',
                'Nominate',
                'The current President creates the successor’s login.',
              ),
              (
                '2',
                'Accept',
                'The successor signs in, changes the temporary password and accepts.',
              ),
              (
                '3',
                'Complete',
                'The current President reconciles pending work and confirms the handover.',
              ),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(radius: 15, child: Text(step.$1)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(step.$2, style: theme.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(step.$3),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
