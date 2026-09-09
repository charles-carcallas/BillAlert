import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/bill.dart';
import '../../domain/value_objects/money.dart';
import '../../domain/value_objects/ph_date.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';

class PostBillAmountState {
  final List<Bill> billsAwaitingAmount;
  final bool isLoading;
  final bool isSubmitting;
  final AppFailure? failure;

  const PostBillAmountState({
    this.billsAwaitingAmount = const [],
    this.isLoading = false,
    this.isSubmitting = false,
    this.failure,
  });

  PostBillAmountState copyWith({
    List<Bill>? billsAwaitingAmount,
    bool? isLoading,
    bool? isSubmitting,
    AppFailure? failure,
  }) {
    return PostBillAmountState(
      billsAwaitingAmount: billsAwaitingAmount ?? this.billsAwaitingAmount,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      failure: failure,
    );
  }
}

class PostBillAmountController extends Notifier<PostBillAmountState> {
  @override
  PostBillAmountState build() {
    Future.microtask(_load);
    return const PostBillAmountState();
  }

  Future<void> _load() async {
    state = state.copyWith(isLoading: true, failure: null);
    
    final user = ref.read(authControllerProvider).value;
    if (user == null || user.areaId == null) {
      state = state.copyWith(
        isLoading: false,
        failure: const ValidationFailure('Not logged in as Admin with an area'),
      );
      return;
    }

    final billRepo = ref.read(billRepositoryProvider);
    final result = await billRepo.awaitingAmount(user.areaId!);
    
    switch (result) {
      case Ok(:final value):
        state = state.copyWith(isLoading: false, billsAwaitingAmount: value);
      case Err(:final failure):
        state = state.copyWith(isLoading: false, failure: failure);
    }
  }

  Future<void> postAmount(Bill bill, Money amount, PhDate dueDate) async {
    state = state.copyWith(isSubmitting: true, failure: null);

    final usecase = ref.read(postBillAmountProvider);
    final result = await usecase(
      bill: bill,
      amount: amount,
      dueDate: dueDate,
    );

    switch (result) {
      case Ok():
        state = state.copyWith(isSubmitting: false);
        // Refresh the list after successful post
        await _load();
      case Err(:final failure):
        state = state.copyWith(isSubmitting: false, failure: failure);
    }
  }

  Future<void> refresh() => _load();
}

final postBillAmountControllerProvider =
    NotifierProvider<PostBillAmountController, PostBillAmountState>(
  PostBillAmountController.new,
);
