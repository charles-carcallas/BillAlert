import '../../domain/repositories/payment_repository.dart';
import '../../domain/value_objects/ph_date.dart';

/// Filters transactions by their actual Philippine payment day, not bill cycle.
/// Both calendar endpoints are inclusive, including a single-day range.
List<PaymentSummary> filterPaymentHistory(
  List<PaymentSummary> receipts, {
  String query = '',
  PhDate? from,
  PhDate? through,
  bool newestFirst = true,
}) {
  final String search = query.trim().toLowerCase();
  return receipts.where((receipt) {
    final PhDate paid = PhDate.at(receipt.paidAt);
    if (from != null && paid.isBefore(from)) return false;
    if (through != null && paid.isAfter(through)) return false;
    return search.isEmpty ||
        receipt.receiptNo.toLowerCase().contains(search) ||
        receipt.bills.any(
          (bill) => bill.cycleLabel.toLowerCase().contains(search),
        );
  }).toList()..sort((a, b) {
    final int byDate = a.paidAt.compareTo(b.paidAt);
    final int order = byDate == 0 ? a.receiptNo.compareTo(b.receiptNo) : byDate;
    return newestFirst ? -order : order;
  });
}
