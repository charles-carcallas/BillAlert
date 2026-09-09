// ============================================================
// WEEK 11 — START HERE   ·   Cashier · Record Payment (controller)
// Owner: Obiso
// Worksheet: docs/week11/worksheets/03_cashier_record_payment.md
//
// PURPOSE
//   Connect the cashier payment screen to the RecordCashPayment use case.
//
// WHERE YOU ARE IN THE CHAIN
//   Screen -> THIS CONTROLLER -> RecordCashPayment (UseCase) -> Repository
//
// CALLS
//   RecordCashPayment
//
// BEFORE CODING
//   - See reference implementation: reading_entry_controller.dart
//
// DO NOT CHANGE
//   The file name or location.
//
// DONE WHEN
//   The controller correctly maps UI actions to the usecase and manages loading/error states.
// ============================================================
// coach:anchor(imports)
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/entities/consumer.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/kwh.dart';
import '../../domain/value_objects/money.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

// coach:anchor(state-class)
class RecordPaymentState {
  final Consumer? selectedConsumer;
  final List<Consumer> searchResults;
  final List<Bill> payableBills;
  final Set<String> selectedBillIds;
  final bool isFetchingBills;
  final bool isSubmitting;
  final AppFailure? failure;
  final String? receiptNumber;

  const RecordPaymentState({
    this.selectedConsumer,
    this.searchResults = const [],
    this.payableBills = const [],
    this.selectedBillIds = const {},
    this.isFetchingBills = false,
    this.isSubmitting = false,
    this.failure,
    this.receiptNumber,
  });

  RecordPaymentState copyWith({
    Consumer? selectedConsumer,
    List<Consumer>? searchResults,
    List<Bill>? payableBills,
    Set<String>? selectedBillIds,
    bool? isFetchingBills,
    bool? isSubmitting,
    AppFailure? failure,
    String? receiptNumber,
  }) {
    return RecordPaymentState(
      selectedConsumer: selectedConsumer ?? this.selectedConsumer,
      searchResults: searchResults ?? this.searchResults,
      payableBills: payableBills ?? this.payableBills,
      selectedBillIds: selectedBillIds ?? this.selectedBillIds,
      isFetchingBills: isFetchingBills ?? this.isFetchingBills,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: failure,
      receiptNumber: receiptNumber ?? this.receiptNumber,
    );
  }

  Money get totalSelected {
    final selected = payableBills.where((b) => selectedBillIds.contains(b.id.value));
    int totalCents = 0;
    for (final b in selected) {
      totalCents += b.balance.centavos;
    }
    return Money.fromCentavos(totalCents);
  }
}

// coach:anchor(controller-class)
class RecordPaymentController extends Notifier<RecordPaymentState> {
  @override
  RecordPaymentState build() {
    return const RecordPaymentState();
  }

  Future<void> searchConsumers(String query) async {
    final user = ref.read(authControllerProvider).value;
    if (user == null || user.areaId == null) return;
    
    if (query.trim().isEmpty) {
      state = state.copyWith(searchResults: []);
      return;
    }

    try {
      final q = query.trim().toLowerCase();
      // Cashiers search live against the outstanding view, not the local cache.
      final rows = await ref.read(supabaseClientProvider)
          .from('v_consumer_outstanding')
          .select()
          .eq('area_id', user.areaId!.value)
          .or('consumer_no.ilike.%$q%,consumer_name.ilike.%$q%')
          .limit(20);
          
      // Map the view rows back to Consumer entities for the UI
      final matches = rows.map((r) => Consumer(
        id: ConsumerId(r['consumer_id'] as String),
        consumerNo: ConsumerNumber(r['consumer_no'] as String),
        firstName: (r['consumer_name'] as String).split(' ').first,
        lastName: (r['consumer_name'] as String).split(' ').skip(1).join(' '),
        areaId: AreaId(r['area_id'] as String),
        accountStatus: AccountStatus.active, // implicit for outstanding view
        previousReading: Kwh.zero, // not needed for payment flow
        purok: r['purok'] as String?,
      )).toList();

      state = state.copyWith(searchResults: matches);
    } catch (e) {
      state = state.copyWith(searchResults: []);
    }
  }

  Future<void> selectConsumer(Consumer consumer) async {
    state = state.copyWith(
      selectedConsumer: consumer,
      searchResults: [],
      isFetchingBills: true,
      failure: null,
      payableBills: [],
      selectedBillIds: {},
      receiptNumber: null,
    );

    final result = await ref.read(billRepositoryProvider).payableFor(consumer.id);
    switch (result) {
      case Ok(:final value):
        state = state.copyWith(
          isFetchingBills: false,
          payableBills: value,
        );
      case Err(:final failure):
        state = state.copyWith(
          isFetchingBills: false,
          failure: failure,
        );
    }
  }

  void toggleBill(Bill bill, bool selected) {
    final ids = Set<String>.from(state.selectedBillIds);
    if (selected) {
      ids.add(bill.id.value);
    } else {
      ids.remove(bill.id.value);
    }
    state = state.copyWith(selectedBillIds: ids, failure: null);
  }

  void clearSelection() {
    state = const RecordPaymentState();
  }

  Future<void> confirmPayment() async {
    if (state.selectedBillIds.isEmpty || state.selectedConsumer == null) {
      state = state.copyWith(failure: const ValidationFailure('No bills selected'));
      return;
    }

    state = state.copyWith(isSubmitting: true, failure: null);

    final usecase = ref.read(recordCashPaymentProvider);
    final selectedBills = state.payableBills
        .where((b) => state.selectedBillIds.contains(b.id.value))
        .toList();
    final amounts = selectedBills.map((b) => b.balance).toList();

    final result = await usecase(
      consumerLabel: state.selectedConsumer!.consumerNo.value,
      bills: selectedBills,
      amounts: amounts,
      cashTendered: state.totalSelected,
    );

    switch (result) {
      case Ok():
        state = state.copyWith(
          isSubmitting: false,
          receiptNumber: 'Payment Queued',
        );
      case Err(:final failure):
        state = state.copyWith(
          isSubmitting: false,
          failure: failure,
        );
    }
  }
}

// coach:anchor(providers)
final recordPaymentControllerProvider =
    NotifierProvider<RecordPaymentController, RecordPaymentState>(
  RecordPaymentController.new,
);
