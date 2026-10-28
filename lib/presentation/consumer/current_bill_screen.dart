import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/app_user.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/consumer.dart' as domain;
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../admin/staff_household_setup.dart';
import '../auth/auth_controller.dart';
import '../common/account_view_menu.dart';
import '../common/collection_deadline.dart';
import '../common/failure_banner.dart';
import '../common/settlement_panel.dart';
import '../providers.dart';
import 'current_bill_controller.dart';
import 'inbox_button.dart';

/// The Consumer's read-only bill overview.
class CurrentBillScreen extends ConsumerWidget {
  const CurrentBillScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(currentBillControllerProvider);
    final PhDate today = ref.watch(phClockProvider).today();
    final AppUser? user = ref.watch(authControllerProvider).value;
    final displayedBill =
        state.history
            .where(
              (bill) => bill.isWaived && bill.cycle == CycleLabel.of(today),
            )
            .firstOrNull ??
        state.currentBill;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ref.read(currentBillControllerProvider.notifier).refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              _GreetingHeader(firstName: user?.firstName),
              const SizedBox(height: 14),
              _HouseholdSummary(household: state.household),
              if (state.household != null)
                HouseholdPaymentRoute(consumerId: state.household!.id.value),
              if (displayedBill != null)
                CollectionDeadline(bill: displayedBill),
              const SizedBox(height: 16),
              if (state.needsHousehold)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'No household linked yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          user is AdminUser
                              ? 'Set up your own electricity household using this login.'
                              : 'Ask your Area President to link your household to this login.',
                        ),
                        if (user is AdminUser)
                          StaffHouseholdSetupButton(
                            person: {
                              'id': user.id.value,
                              'first_name': user.firstName,
                              'last_name': user.lastName,
                            },
                            label: 'Set up my household',
                          ),
                      ],
                    ),
                  ),
                ),
              if (state.failure != null) ...<Widget>[
                FailureBanner(
                  failure: state.failure!,
                  onRetry: ref
                      .read(currentBillControllerProvider.notifier)
                      .refresh,
                ),
                const SizedBox(height: 12),
              ],
              if (state.isLoading && displayedBill == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 64),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (displayedBill == null &&
                  !state.isLoading &&
                  !state.needsHousehold &&
                  state.failure == null)
                _NoCurrentBill(history: state.history, today: today)
              else if (displayedBill case final Bill bill) ...<Widget>[
                _CurrentAmountPanel(
                  bill: bill,
                  today: today,
                  earlier: _earlierUnpaid(bill, state.history),
                ),
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

  const _GreetingHeader({required this.firstName});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
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
        const InboxButton(),
        const AccountViewMenu(),
      ],
    );
  }
}

class _HouseholdSummary extends StatelessWidget {
  const _HouseholdSummary({required this.household});
  final domain.Consumer? household;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meter = household?.meterSerialNo?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.home_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Text('My household', style: theme.textTheme.titleSmall),
          ],
        ),
        if (household case final domain.Consumer home) ...[
          const SizedBox(height: 6),
          DefaultTextStyle(
            style: theme.textTheme.bodySmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                Text('Consumer no. ${home.consumerNo.value}'),
                if (meter != null && meter.isNotEmpty) Text('Meter $meter'),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// The bills behind this one that are still owed.
///
/// The headline on this screen used to be one month's balance, which is not
/// what a household owes: a July bill left unpaid does not stop being owed
/// when August arrives, and it was only visible by scrolling History. The
/// panel adds them up instead, and shows the parts underneath so the total
/// is never a figure nobody can account for.
///
/// Sorted oldest first, which is the order a cashier settles them in.
/// Unpriced bills contribute nothing — `Bill.balance` is zero until the
/// cooperative posts an amount, so a reading with no peso figure can never
/// inflate what a household is told it owes.
///
/// Drawn from the loaded history, which is the most recent twelve cycles.
/// A debt older than that is not counted here; `v_consumer_outstanding` is
/// the server's own total and is what the Cashier's screen trusts.
List<Bill> _earlierUnpaid(Bill current, List<Bill> history) {
  final List<Bill> earlier =
      history
          .where(
            (Bill other) =>
                other.id != current.id && other.isPayable && !other.isSettled,
          )
          .toList()
        ..sort((Bill a, Bill b) => a.cycle.compareTo(b.cycle));
  return earlier;
}

class _CurrentAmountPanel extends StatelessWidget {
  final Bill bill;
  final PhDate today;
  final List<Bill> earlier;

  const _CurrentAmountPanel({
    required this.bill,
    required this.today,
    required this.earlier,
  });

  /// Everything the household still owes, this month and before.
  Money get _totalUnpaid => earlier.fold<Money>(
    bill.balance,
    (Money running, Bill other) => running + other.balance,
  );

  /// "Amount pending" belongs on a screen with nothing owed on it. Once an
  /// older bill is outstanding there is a real figure to show, and an
  /// unpriced current month must not hide it behind the word "pending".
  bool get _showsPending => bill.isUnpriced && earlier.isEmpty;

  String get _headline {
    if (_showsPending) return 'Current billing month';
    if (earlier.isEmpty) return 'Amount due';
    return 'Total amount unpaid';
  }

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
          // "Amount due" was the balance of one month. It is only the whole
          // truth when nothing older is outstanding, so the label says which
          // of the two it is rather than quietly meaning both.
          Text(_headline, style: text.bodyMedium),
          const SizedBox(height: 4),
          Text(
            _showsPending ? 'Amount pending' : _totalUnpaid.format(),
            style: text.headlineMedium?.copyWith(
              fontSize: _showsPending ? 28 : 42,
              height: 1.15,
              letterSpacing: -1,
              fontWeight: FontWeight.w700,
            ),
          ),
          // The total broken into the months it came from. Shown only when
          // there is something older, because with one bill the breakdown
          // would just repeat the figure above it.
          if (earlier.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _UnpaidLine(
              label: bill.isUnpriced
                  ? '${bill.cycle.displayName} (awaiting amount)'
                  : '${bill.cycle.displayName} (this bill)',
              value: bill.isUnpriced ? null : bill.balance,
            ),
            const SizedBox(height: 6),
            for (final Bill other in earlier) ...<Widget>[
              _UnpaidLine(
                label: '${other.cycle.displayName} (unpaid)',
                value: other.balance,
                overdue: other.isOverdueOn(today),
              ),
              const SizedBox(height: 6),
            ],
          ],
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
          if (bill.isWaived) ...<Widget>[
            const SizedBox(height: 14),
            _BillFact(
              label: 'BOHECO coverage',
              value: bill.waiverAmount.format(),
            ),
          ],
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
        ? bill.statusLabelOn(today)
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
            overdue
                ? Icons.error_outline
                : bill.isSettled
                ? Icons.check_circle_outline
                : Icons.schedule_outlined,
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

/// One month's share of the total, as a label and a figure.
class _UnpaidLine extends StatelessWidget {
  final String label;

  /// Null for a bill the cooperative has not priced, which is owed nothing
  /// yet and must not be printed as a zero peso debt.
  final Money? value;
  final bool overdue;

  const _UnpaidLine({
    required this.label,
    required this.value,
    this.overdue = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final Money? amount = value;

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: text.bodySmall?.copyWith(
              color: overdue ? colours.error : null,
              fontWeight: overdue ? FontWeight.w600 : null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          amount == null ? 'Not posted yet' : amount.format(),
          style: text.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: overdue ? colours.error : null,
          ),
        ),
      ],
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
  final PhDate today;

  const _NoCurrentBill({required this.history, required this.today});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    final settled = history.where((bill) => bill.isSettled).toList()
      ..sort((a, b) => b.cycle.compareTo(a.cycle));
    final latestPaid = settled.firstOrNull;
    final hasBillingHistory = history.isNotEmpty;
    final month = CycleLabel.of(today).displayName;
    final monthName = month.substring(0, month.lastIndexOf(' '));

    return Container(
      key: const ValueKey('household-empty-bill'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLow,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colours.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  hasBillingHistory
                      ? Icons.task_alt
                      : Icons.description_outlined,
                  color: colours.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      month,
                      style: text.labelMedium?.copyWith(
                        color: colours.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasBillingHistory
                          ? 'You’re all caught up'
                          : 'No bill for $monthName yet',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            hasBillingHistory
                ? 'You have no unpaid bills right now.'
                : 'Your bill will appear after your meter reading is recorded.',
            style: text.bodyMedium?.copyWith(color: colours.onSurfaceVariant),
          ),
          if (latestPaid != null) ...[
            const SizedBox(height: 12),
            Text(
              '${latestPaid.isWaived ? 'Latest covered bill' : 'Latest paid bill'} · ${latestPaid.cycle.displayName}',
              style: text.bodySmall?.copyWith(color: colours.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => context.go('/consumer/history'),
            icon: const Icon(Icons.history, size: 18),
            label: const Text('View billing history'),
          ),
        ],
      ),
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
