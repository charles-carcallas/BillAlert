import '../../domain/repositories/payment_repository.dart';

/// Whether a loaded receipt matches the Cashier's local search.
bool paymentMatchesSearch(PaymentSummary payment, String rawQuery) {
  final String query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;

  return payment.consumerName.toLowerCase().contains(query) ||
      payment.receiptNo.toLowerCase().contains(query);
}
