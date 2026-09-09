import 'dart:async';

// `Consumer` in this app means a household. Riverpod's Consumer widget is not
// used in this file, so the package's name is hidden rather than the domain's
// word being changed to suit it.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/repositories/bill_repository.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

/// The state of the counter: who is standing there, what they owe, what they
/// have chosen to settle and what they handed over.
final class RecordPaymentState {
  /// Every household in this area with something outstanding.
  final List<ConsumerOutstanding> households;

  /// What the cashier has typed into the search box.
  final String query;

  final ConsumerOutstanding? selected;

  /// CSH-02: only priced, unsettled bills. An unpriced bill can never appear
  /// here - there is no figure to pay.
  final List<Bill> payableBills;

  final Set<String> selectedBillIds;

  /// The cash handed over, as typed. Text, not a number: it becomes [Money]
  /// through Money.tryParse and never passes through a double.
  final String cashTenderedText;

  final bool isLoadingHouseholds;
  final bool isLoadingBills;
  final bool isSubmitting;
  final AppFailure? failure;

  /// The receipt, once the handover has reached the server. Null while the
  /// payment is only in the outbox.
  final PaymentSummary? receipt;

  /// True when the payment is safely queued but has not synced, so the screen
  /// can say that rather than invent a receipt number.
  final bool queuedOffline;

  const RecordPaymentState({
    this.households = const <ConsumerOutstanding>[],
    this.query = '',
    this.selected,
    this.payableBills = const <Bill>[],
    this.selectedBillIds = const <String>{},
    this.cashTenderedText = '',
    this.isLoadingHouseholds = false,
    this.isLoadingBills = false,
    this.isSubmitting = false,
    this.failure,
    this.receipt,
    this.queuedOffline = false,
  });

  RecordPaymentState copyWith({
    List<ConsumerOutstanding>? households,
    String? query,
    ConsumerOutstanding? selected,
    List<Bill>? payableBills,
    Set<String>? selectedBillIds,
    String? cashTenderedText,
    bool? isLoadingHouseholds,
    bool? isLoadingBills,
    bool? isSubmitting,
    AppFailure? failure,
    PaymentSummary? receipt,
    bool? queuedOffline,
    bool clearSelected = false,
  }) {
    return RecordPaymentState(
      households: households ?? this.households,
      query: query ?? this.query,
      selected: clearSelected ? null : (selected ?? this.selected),
      payableBills: payableBills ?? this.payableBills,
      selectedBillIds: selectedBillIds ?? this.selectedBillIds,
      cashTenderedText: cashTenderedText ?? this.cashTenderedText,
      isLoadingHouseholds: isLoadingHouseholds ?? this.isLoadingHouseholds,
      isLoadingBills: isLoadingBills ?? this.isLoadingBills,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      // A stale failure or a stale receipt is worse than none, so both are
      // cleared by omission rather than carried forward.
      failure: failure,
      receipt: receipt,
      queuedOffline: queuedOffline ?? false,
    );
  }

  /// The households matching what has been typed.
  List<ConsumerOutstanding> get visibleHouseholds =>
      households.where((ConsumerOutstanding c) => c.matches(query)).toList();

  List<Bill> get selectedBills => payableBills
      .where((Bill b) => selectedBillIds.contains(b.id.value))
      .toList();

  /// What this handover comes to.
  ///
  /// Adding Money to Money, which is the one arithmetic the domain allows on
  /// it. This is not deriving a bill - every figure being added was decided by
  /// the cooperative and typed in by the Admin.
  Money get total => selectedBills.fold(
        Money.zero,
        (Money running, Bill bill) => running + bill.balance,
      );

  /// Null when the box is empty or does not read as an amount.
  Money? get cashTendered => Money.tryParse(cashTenderedText);

  /// Change owed, or null when there is nothing to work it out from.
  Money? get change {
    final Money? tendered = cashTendered;
    if (tendered == null || tendered < total) return null;
    return tendered - total;
  }

  bool get canConfirm =>
      selectedBillIds.isNotEmpty && !isSubmitting && !isLoadingBills;
}

/// FR-30 — the cashier takes cash across the counter.
///
/// One handover is one transaction and one receipt, however many months it
/// settles. That is why [confirm] makes a single call: `fn_record_payment`
/// takes the bill ids and the amounts as parallel lists and settles them in
/// one transaction. A loop of one call per bill would leave a consumer
/// half-paid the first time the network dropped mid-loop.
class RecordPaymentController extends Notifier<RecordPaymentState> {
  Future<void>? _inFlightHouseholds;

  @override
  RecordPaymentState build() {
    Future<void>.microtask(loadHouseholds);
    return const RecordPaymentState(isLoadingHouseholds: true);
  }

  /// Coalesced, for the same reason the Admin queue is: build() starts one and
  /// pull-to-refresh starts another, and the slower one must not land last
  /// with a stale answer.
  Future<void> loadHouseholds() {
    final Future<void>? existing = _inFlightHouseholds;
    if (existing != null) return existing;

    final Future<void> load =
        _doLoadHouseholds().whenComplete(() => _inFlightHouseholds = null);
    _inFlightHouseholds = load;
    return load;
  }

  Future<void> _doLoadHouseholds() async {
    final user = await ref.read(authControllerProvider.future);
    final AreaId? areaId = user?.areaId;

    if (areaId == null) {
      state = state.copyWith(
        isLoadingHouseholds: false,
        failure: const PermissionFailure(
          'This screen is for a cashier, and no service area is attached to '
          'the account you are signed in with.',
        ),
      );
      return;
    }

    state = state.copyWith(isLoadingHouseholds: true);

    switch (await ref.read(billRepositoryProvider).outstandingInArea(areaId)) {
      case Ok(:final value):
        state = state.copyWith(households: value, isLoadingHouseholds: false);
      case Err(:final failure):
        state = state.copyWith(isLoadingHouseholds: false, failure: failure);
    }
  }

  /// Filters the list already on the phone rather than asking the server on
  /// every keystroke. One area is a few dozen households, and the cashier is
  /// typing while somebody waits at the counter.
  void search(String query) => state = state.copyWith(query: query);

  Future<void> selectHousehold(ConsumerOutstanding household) async {
    state = state.copyWith(
      selected: household,
      payableBills: const <Bill>[],
      selectedBillIds: const <String>{},
      cashTenderedText: '',
      isLoadingBills: true,
    );

    switch (await ref.read(billRepositoryProvider).payableFor(household.consumerId)) {
      case Ok(:final value):
        state = state.copyWith(payableBills: value, isLoadingBills: false);
      case Err(:final failure):
        state = state.copyWith(isLoadingBills: false, failure: failure);
    }
  }

  void toggleBill(Bill bill, bool selected) {
    final ids = Set<String>.from(state.selectedBillIds);
    if (selected) {
      ids.add(bill.id.value);
    } else {
      ids.remove(bill.id.value);
    }
    state = state.copyWith(selectedBillIds: ids);
  }

  /// Selects every month at once, which is what "settle everything" means and
  /// is the common case at the counter.
  void selectAll() => state = state.copyWith(
        selectedBillIds:
            state.payableBills.map((Bill b) => b.id.value).toSet(),
      );

  void setCashTendered(String text) =>
      state = state.copyWith(cashTenderedText: text);

  /// Back to the household list, ready for the next person.
  void startNewPayment() {
    state = state.copyWith(
      clearSelected: true,
      payableBills: const <Bill>[],
      selectedBillIds: const <String>{},
      cashTenderedText: '',
      query: '',
    );
    unawaited(loadHouseholds());
  }

  /// Records the handover: one call, however many bills.
  Future<void> confirm() async {
    final ConsumerOutstanding? household = state.selected;
    if (household == null) return;

    final List<Bill> bills = state.selectedBills;
    if (bills.isEmpty) {
      state = state.copyWith(
        failure: const ValidationFailure(
          'Choose at least one month before recording a payment.',
        ),
      );
      return;
    }

    // Each selected month is settled in full. The use case checks every
    // amount against its own bill's balance, so a bill can never be
    // over-collected even if this list is wrong.
    final List<Money> amounts = bills.map((Bill b) => b.balance).toList();

    // Empty box means the cashier did not record the cash. That is allowed -
    // the column is nullable - and is not the same as zero.
    final Money? tendered =
        state.cashTenderedText.trim().isEmpty ? null : state.cashTendered;
    if (state.cashTenderedText.trim().isNotEmpty && tendered == null) {
      state = state.copyWith(
        failure: const ValidationFailure(
          'Enter the cash received as an amount, for example 1500 or 1500.00.',
        ),
      );
      return;
    }

    state = state.copyWith(isSubmitting: true);

    final result = await ref.read(recordCashPaymentProvider)(
      consumerLabel: household.consumerNo.value,
      bills: bills,
      amounts: amounts,
      cashTendered: tendered,
    );

    switch (result) {
      case Err(:final failure):
        state = state.copyWith(isSubmitting: false, failure: failure);

      case Ok():
        // The handover is safe in the outbox. Draining it is what produces the
        // official receipt, so it is awaited: the consumer is standing at the
        // counter waiting to be handed one.
        await ref.read(syncServiceProvider).syncNow();
        await _fetchReceipt(household.consumerId);
    }
  }

  /// Reads back the receipt the server issued.
  ///
  /// The receipt number is the server's to mint - `fn_record_payment` builds
  /// it from a sequence - so the app asks for it rather than inventing one.
  /// If it is not there yet the payment is queued, not lost, and the screen
  /// says exactly that.
  Future<void> _fetchReceipt(ConsumerId consumerId) async {
    switch (await ref.read(paymentRepositoryProvider).historyFor(consumerId)) {
      case Ok(:final value) when value.isNotEmpty:
        // historyFor returns newest first, so the handover just recorded is
        // the first one.
        state = state.copyWith(isSubmitting: false, receipt: value.first);
      case Ok():
        state = state.copyWith(isSubmitting: false, queuedOffline: true);
      case Err():
        // The money is recorded; only the receipt lookup failed. Saying
        // "queued" is true and is better than showing an error for something
        // that did work.
        state = state.copyWith(isSubmitting: false, queuedOffline: true);
    }
  }
}

final recordPaymentControllerProvider =
    NotifierProvider<RecordPaymentController, RecordPaymentState>(
  RecordPaymentController.new,
);
