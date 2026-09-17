import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/expandable_bottom_sheet.dart';
import '../common/failure_banner.dart';
import '../common/final_confirmation_dialog.dart';
import 'contact_number_controller.dart';

Future<String?> showEditConsumerContactNumber(
  BuildContext context, {
  String? currentNumber,
}) => showExpandableBottomSheet<String>(
  context: context,
  initialSize: 0.6,
  builder: (_, ScrollController scrollController) =>
      EditConsumerContactNumberSheet(
        currentNumber: currentNumber,
        scrollController: scrollController,
      ),
);

class EditConsumerContactNumberSheet extends ConsumerStatefulWidget {
  final String? currentNumber;
  final ScrollController? scrollController;

  const EditConsumerContactNumberSheet({
    this.currentNumber,
    this.scrollController,
    super.key,
  });

  @override
  ConsumerState<EditConsumerContactNumberSheet> createState() =>
      _EditConsumerContactNumberSheetState();
}

class _EditConsumerContactNumberSheetState
    extends ConsumerState<EditConsumerContactNumberSheet> {
  late final TextEditingController _number;

  @override
  void initState() {
    super.initState();
    _number = TextEditingController(text: widget.currentNumber);
    // Riverpod does not allow state changes while this route is mounting.
    // Clear any result from a previous visit immediately after this frame.
    Future<void>.microtask(() {
      if (mounted) {
        ref.read(consumerContactNumberControllerProvider.notifier).reset();
      }
    });
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _review() async {
    final String typed = _number.text;
    final bool confirmed = await showFinalConfirmation(
      context,
      title: 'Update SMS number?',
      subject: 'Change where this household receives SMS alerts',
      details: <ConfirmationDetail>[
        ConfirmationDetail('New mobile number', typed),
      ],
      warning:
          'Future bill reminders and disconnection notices will be sent to '
          'this number. The server will format it after you confirm.',
      confirmLabel: 'Update number',
    );
    if (!confirmed || !mounted) return;

    final controller = ref.read(
      consumerContactNumberControllerProvider.notifier,
    );
    await controller.update(typed);
    if (!mounted) return;

    final state = ref.read(consumerContactNumberControllerProvider);
    if (state.savedNumber != null) {
      Navigator.of(context).pop(state.savedNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(consumerContactNumberControllerProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      child: SingleChildScrollView(
        controller: widget.scrollController,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'SMS delivery number',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: state.isSubmitting
                      ? null
                      : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Bill reminders, overdue alerts, and disconnection notices use '
              'this number.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              key: const ValueKey<String>('consumer-contact-number'),
              controller: _number,
              enabled: !state.isSubmitting,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _review(),
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                hintText: '0917 555 0142',
                helperText: 'Philippine mobile number',
              ),
            ),
            if (state.failure != null) ...<Widget>[
              const SizedBox(height: 14),
              FailureBanner(failure: state.failure!),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: state.isSubmitting ? null : _review,
              child: state.isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Review new number'),
            ),
          ],
        ),
      ),
    );
  }
}
