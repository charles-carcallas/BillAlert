import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/entities/bill.dart';
import '../../domain/value_objects/ph_date.dart';
import '../auth/auth_controller.dart';
import '../common/failure_banner.dart';
import '../providers.dart';
import 'current_bill_controller.dart';
import 'inbox_controller.dart';

/// The Consumer's read-only bill overview.
class CurrentBillScreen extends ConsumerWidget {
  const CurrentBillScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(currentBillControllerProvider);
    final PhDate today = ref.watch(phClockProvider).today();
    final AppUser? user = ref.watch(authControllerProvider).value;
    final int unread = ref.watch(inboxControllerProvider).unreadCount;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ref.read(currentBillControllerProvider.notifier).refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              _GreetingHeader(firstName: user?.firstName, unread: unread),
              const SizedBox(height: 16),
              if (state.failure != null) ...<Widget>[
                FailureBanner(
                  failure: state.failure!,
                  onRetry: ref
                      .read(currentBillControllerProvider.notifier)
                      .refresh,
                ),
                const SizedBox(height: 12),
              ],
              if (state.isLoading && state.currentBill == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.currentBill == null &&
                  !state.isLoading &&
                  state.failure == null)
                _NoCurrentBill(history: state.history)
              else if (state.currentBill case final Bill bill) ...<Widget>[
                _CurrentAmountPanel(bill: bill, today: today),
                if (bill.isOverdueOn(today)) ...<Widget>[
                  const SizedBox(height: 14),
                  _PastDueNotice(bill: bill),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GreetingHeader extends StatelessWidget {
  final String? firstName;
  final int unread;

  const _GreetingHeader({required this.firstName, required this.unread});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    final String name = firstName?.trim().isNotEmpty == true
        ? firstName!.trim()
        : 'there';

    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Welcome back,', style: text.bodyMedium),
              Text(
                name,
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Open inbox',
          onPressed: () => context.go('/consumer/inbox'),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: Icon(
              unread > 0
                  ? Icons.notifications
                  : Icons.notifications_none_outlined,
              color: colours.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _CurrentAmountPanel extends StatelessWidget {
  final Bill bill;
  final PhDate today;

  const _CurrentAmountPanel({required this.bill, required this.today});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    final bool overdue = bill.isOverdueOn(today);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            bill.isUnpriced ? 'Current billing month' : 'Amount due',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            bill.isUnpriced ? 'Amount pending' : bill.balance.format(),
            style: text.headlineMedium?.copyWith(
              fontSize: bill.isUnpriced ? 28 : 42,
              height: 1.15,
              letterSpacing: -1,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _BillStatusLine(bill: bill, today: today),
          const SizedBox(height: 18),
          Divider(color: colours.outlineVariant),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: _BillFact(
                  label: 'Consumption',
                  value: bill.consumption.format(),
                ),
              ),
              Expanded(
                child: _BillFact(
                  label: 'Billing month',
                  value: bill.cycle.displayName,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _BillFact(label: 'Bill number', value: bill.billNo.value),
          if (bill.isUnpriced) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              'The cooperative has not posted the amount yet. It will appear '
              'here when it is ready.',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: 18),
          Material(
            color: colours.primary.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.go('/consumer/history'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        overdue ? 'View payment history' : 'View bill history',
                        style: text.titleSmall?.copyWith(
                          color: colours.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right, size: 20, color: colours.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillStatusLine extends StatelessWidget {
  final Bill bill;
  final PhDate today;

  const _BillStatusLine({required this.bill, required this.today});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    final bool overdue = bill.isOverdueOn(today);
    final Color colour = overdue ? colours.error : colours.primary;
    final String label = bill.isUnpriced
        ? 'Awaiting the cooperative amount'
        : overdue
        ? 'Overdue · due ${_friendlyDate(bill.dueDate!)}'
        : bill.isSettled
        ? 'Paid'
        : 'Due ${_friendlyDate(bill.dueDate!)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            overdue ? Icons.error_outline : Icons.schedule_outlined,
            size: 17,
            color: colour,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: colour,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillFact extends StatelessWidget {
  final String label;
  final String value;

  const _BillFact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: text.bodySmall),
        const SizedBox(height: 3),
        Text(
          value,
          style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _PastDueNotice extends StatelessWidget {
  final Bill bill;

  const _PastDueNotice({required this.bill});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colours.errorContainer.withValues(alpha: 0.55),
        border: Border.all(color: colours.error.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: colours.error,
            foregroundColor: colours.onError,
            child: const Icon(Icons.warning_amber_rounded, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Past due',
                        style: text.titleSmall?.copyWith(
                          color: colours.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      bill.balance.format(),
                      style: text.titleSmall?.copyWith(
                        color: colours.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${bill.cycle.displayName} remains unpaid.',
                  style: text.bodySmall?.copyWith(color: colours.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoCurrentBill extends StatelessWidget {
  final List<Bill> history;

  const _NoCurrentBill({required this.history});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    final List<Bill> settled =
        history.where((Bill bill) => bill.isSettled).toList()
          ..sort((Bill a, Bill b) => b.cycle.compareTo(a.cycle));
    final Bill? latestPaid = settled.isEmpty ? null : settled.first;
    final bool hasBillingHistory = history.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Keep the primary card in the same place on every visit. With no
        // payable bill its value area is deliberately blank: ₱0.00 would
        // look like a real bill amount, which the server never issued.
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colours.surfaceContainerLowest,
            border: Border.all(color: colours.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Amount due', style: text.bodyMedium),
              const SizedBox(height: 4),
              const SizedBox(height: 48),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colours.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      hasBillingHistory
                          ? Icons.check_circle_outline
                          : Icons.schedule_outlined,
                      size: 17,
                      color: colours.primary,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      hasBillingHistory
                          ? 'No payment needed'
                          : 'No current bill',
                      style: text.titleSmall?.copyWith(
                        color: colours.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colours.surfaceContainerLowest,
            border: Border.all(color: colours.outlineVariant),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: <Widget>[
              Icon(
                hasBillingHistory ? Icons.task_alt : Icons.description_outlined,
                size: 42,
                color: colours.primary,
              ),
              const SizedBox(height: 12),
              Text(
                hasBillingHistory
                    ? 'You’re all caught up'
                    : 'No current bill yet',
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                hasBillingHistory
                    ? 'You have no unpaid bills right now.'
                    : 'Your current bill will appear after your meter has '
                          'been read.',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (latestPaid != null) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  'Latest paid bill · ${latestPaid.cycle.displayName}',
                  style: text.bodySmall?.copyWith(
                    color: colours.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/consumer/history'),
                  icon: const Icon(Icons.history),
                  label: const Text('View billing history'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _friendlyDate(PhDate date) {
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
