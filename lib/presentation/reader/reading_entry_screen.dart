import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// `Consumer` here means a household, which is the domain's word for it.
// Riverpod's Consumer widget is not used in this file, so it is hidden
// rather than the entity being renamed to suit a package.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/usecases/reader/record_meter_reading.dart';
import '../../domain/value_objects/kwh.dart';
import '../common/failure_banner.dart';
import 'reading_entry_controller.dart';

/// FR-21a — recording one household's reading.
///
/// The screen shows the previous reading and the consumption as the reader
/// types, and it shows no peso amount anywhere, because there is not one. A
/// reading creates an unpriced bill; the cooperative sends the figure about a
/// week later and the Area President posts it.
class ReadingEntryScreen extends ConsumerStatefulWidget {
  final String consumerId;

  const ReadingEntryScreen({required this.consumerId, super.key});

  @override
  ConsumerState<ReadingEntryScreen> createState() => _ReadingEntryScreenState();
}

class _ReadingEntryScreenState extends ConsumerState<ReadingEntryScreen> {
  final TextEditingController _reading = TextEditingController();

  @override
  void dispose() {
    _reading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final household = ref.watch(consumerByIdProvider(widget.consumerId));
    final entry = ref.watch(readingEntryControllerProvider);

    // The save succeeded. Show the confirmation instead of the form: the
    // reading is on the phone, whether or not it has been uploaded.
    final saved = entry.saved;
    if (saved != null) {
      return _SavedConfirmation(reading: saved);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Record reading')),
      body: SafeArea(
        child: household.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => Padding(
            padding: const EdgeInsets.all(16),
            child: FailureBanner(
              failure: error is AppFailure
                  ? error
                  : ServerFailure(ServerFailure.defaultMessage, '$error'),
            ),
          ),
          data: (Consumer? consumer) {
            if (consumer == null) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: FailureBanner(
                  failure: ValidationFailure(
                    'That household is not saved on this phone. Pull down on '
                    'your round to load it while you have a connection.',
                  ),
                ),
              );
            }
            return _Form(
              consumer: consumer,
              controller: _reading,
              state: entry,
              onSave: () => ref
                  .read(readingEntryControllerProvider.notifier)
                  .save(consumer: consumer, enteredReading: _reading.text),
            );
          },
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  final Consumer consumer;
  final TextEditingController controller;
  final ReadingEntryState state;
  final VoidCallback onSave;

  const _Form({
    required this.consumer,
    required this.controller,
    required this.state,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  consumer.fullName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(consumer.consumerNo.value),
                if (consumer.purok != null) Text(consumer.purok!),
                if (consumer.meterSerialNo != null)
                  Text('Meter ${consumer.meterSerialNo}'),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text('Previous reading'),
                    Text(
                      consumer.previousReading.format(),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: const InputDecoration(
            labelText: 'Present reading',
            suffixText: 'kWh',
          ),
        ),
        const SizedBox(height: 12),
        // Live consumption. Energy only — there is deliberately no peso
        // figure on this screen, because the app never computes one.
        ListenableBuilder(
          listenable: controller,
          builder: (BuildContext context, Widget? _) {
            final typed = Kwh.tryParse(controller.text);
            final isPlausible =
                typed != null && consumer.isPlausibleReading(typed);

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Text('Consumption'),
                Text(
                  typed == null
                      ? '—'
                      : isPlausible
                          ? consumer.consumptionFor(typed).format()
                          : 'lower than the last reading',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: typed != null && !isPlausible
                        ? Theme.of(context).colorScheme.error
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
        if (state.failure != null) ...<Widget>[
          const SizedBox(height: 16),
          FailureBanner(failure: state.failure!),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: state.isSaving ? null : onSave,
          child: state.isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save reading'),
        ),
        const SizedBox(height: 8),
        Text(
          'Saved on this phone straight away. It syncs by itself when you '
          'have a signal.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SavedConfirmation extends ConsumerWidget {
  final RecordedReading reading;

  const _SavedConfirmation({required this.reading});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Icon(
                Icons.check_circle,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Reading saved',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                reading.consumerLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              _Line(label: 'Previous', value: reading.previousReading.format()),
              _Line(label: 'Present', value: reading.currentReading.format()),
              _Line(label: 'Consumption', value: reading.consumption.format()),
              _Line(label: 'Date read', value: reading.readingDate.toIso()),
              const SizedBox(height: 24),
              // The one sentence that explains the whole application.
              Text(
                'The amount will appear once the cooperative sends it and '
                'your Area President posts it.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  ref
                      .read(readingEntryControllerProvider.notifier)
                      .dismissFailure();
                  // Pop, because the round is still underneath — the form is
                  // pushed on top of it now rather than replacing it, so the
                  // back arrow and Android's back button both work. `go` is
                  // kept as the fallback for arriving here by deep link,
                  // where there is nothing to pop back to.
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/reader');
                  }
                },
                child: const Text('Back to my round'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;

  const _Line({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
