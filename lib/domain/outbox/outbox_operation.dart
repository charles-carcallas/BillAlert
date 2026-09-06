import '../../core/result/result.dart';
import '../value_objects/cycle_label.dart';
import '../value_objects/ids.dart';
import '../value_objects/kwh.dart';
import '../value_objects/money.dart';
import '../value_objects/ph_date.dart';

/// Something the user did that has not reached the server yet.
///
/// All four roles work offline: the reader captures readings and serves
/// notices, the Admin posts amounts, the cashier takes payments. Each of
/// those is a subclass here, and each one knows two things — how to write
/// itself down, and how to send itself.
///
/// That second part is why this is a sealed class and not an enum with a
/// payload blob. [SyncService] holds a list of `OutboxOperation` and calls
/// `submit()` on each; there is no `switch` on an operation string anywhere
/// in the sync loop. Adding a fifth kind of queued action means writing one
/// new subclass, not editing a switch in three files and hoping you found
/// them all.
///
/// [OutboxGateway] is declared in this file on purpose: it is the other half
/// of the same contract, and separating them would only create a circular
/// import.
sealed class OutboxOperation {
  /// Minted on the device when the action is created, and never again.
  ///
  /// This is what makes a retried sync safe. Every one of the Postgres
  /// functions takes a `p_client_uuid` and looks it up before doing anything,
  /// so uploading the same reading twice returns the original bill instead of
  /// creating a second one. Regenerating it on retry would defeat the whole
  /// mechanism.
  final ClientUuid clientUuid;

  /// The instant the user did this, in UTC — not the instant it synced.
  ///
  /// The server records it as `captured_at`, and the 48-hour disconnection
  /// notice period is counted from it, so this has legal meaning in the
  /// domain and cannot be quietly replaced with "now" at upload time.
  final DateTime capturedAt;

  const OutboxOperation({required this.clientUuid, required this.capturedAt});

  /// Matches the `operation` CHECK constraint on the local `outbox` table.
  String get operationCode;

  /// The fields of this operation, as stored in `outbox.payload_json`.
  /// Domain-shaped keys; the gateway translates them into RPC arguments.
  Map<String, Object?> toPayloadJson();

  /// One line for the "waiting to sync" list.
  String get description;

  /// Sends itself. Returns the server-side id it created.
  Future<Result<String>> submit(OutboxGateway gateway);
}

/// FR-21a — the meter reader captured a reading.
final class RecordReadingOperation extends OutboxOperation {
  final ConsumerId consumerId;
  final Kwh currentReading;

  /// The cycle this reading belongs to, computed in Philippine time. Written
  /// to `outbox_reading_keys` so a second reading for the same consumer and
  /// cycle is refused locally, at the meter.
  final CycleLabel cycleLabel;

  /// Only for the queue display, so the list does not have to look consumers
  /// up while offline.
  final String consumerLabel;

  const RecordReadingOperation({
    required super.clientUuid,
    required super.capturedAt,
    required this.consumerId,
    required this.currentReading,
    required this.cycleLabel,
    required this.consumerLabel,
  });

  @override
  String get operationCode => 'record_reading';

  @override
  Map<String, Object?> toPayloadJson() => <String, Object?>{
        'consumer_id': consumerId.value,
        'current_reading': currentReading.toDatabaseString(),
        'cycle_label': cycleLabel.value,
        'consumer_label': consumerLabel,
      };

  @override
  String get description => 'Reading for $consumerLabel';

  @override
  Future<Result<String>> submit(OutboxGateway gateway) =>
      gateway.submitReading(this);
}

/// FR-21b — the Admin posted the amount the cooperative returned.
final class PostAmountOperation extends OutboxOperation {
  final BillId billId;
  final Money amount;
  final PhDate dueDate;
  final String billLabel;

  const PostAmountOperation({
    required super.clientUuid,
    required super.capturedAt,
    required this.billId,
    required this.amount,
    required this.dueDate,
    required this.billLabel,
  });

  @override
  String get operationCode => 'post_amount';

  @override
  Map<String, Object?> toPayloadJson() => <String, Object?>{
        'bill_id': billId.value,
        'amount': amount.toDatabaseString(),
        'due_date': dueDate.toIso(),
        'bill_label': billLabel,
      };

  @override
  String get description => 'Amount ${amount.format()} for $billLabel';

  @override
  Future<Result<String>> submit(OutboxGateway gateway) =>
      gateway.submitPostedAmount(this);
}

/// FR-30 — the cashier took cash across the counter.
///
/// One handover settles however many bills it covers, and produces one
/// receipt. The bills and the amounts stay as parallel lists because that is
/// exactly what `fn_record_payment(p_bill_ids[], p_amounts[])` takes, and
/// splitting the handover into one call per bill would break its atomicity.
final class RecordPaymentOperation extends OutboxOperation {
  final List<BillId> billIds;
  final List<Money> amounts;
  final Money? cashTendered;
  final String consumerLabel;

  const RecordPaymentOperation({
    required super.clientUuid,
    required super.capturedAt,
    required this.billIds,
    required this.amounts,
    required this.consumerLabel,
    this.cashTendered,
  });

  /// The total handed over. Adding Money to Money, which is safe — this is
  /// not deriving a bill, it is summing amounts a person already decided.
  Money get totalPaid =>
      amounts.fold(Money.zero, (Money running, Money each) => running + each);

  @override
  String get operationCode => 'record_payment';

  @override
  Map<String, Object?> toPayloadJson() => <String, Object?>{
        'bill_ids': billIds.map((BillId id) => id.value).toList(),
        'amounts': amounts.map((Money a) => a.toDatabaseString()).toList(),
        'cash_tendered': cashTendered?.toDatabaseString(),
        'consumer_label': consumerLabel,
      };

  @override
  String get description =>
      'Payment ${totalPaid.format()} from $consumerLabel';

  @override
  Future<Result<String>> submit(OutboxGateway gateway) =>
      gateway.submitPayment(this);
}

/// The Admin served a disconnection notice.
///
/// [capturedAt] is the moment it was served, and the 48-hour period runs from
/// there — not from whenever the phone next found signal.
final class IssueNoticeOperation extends OutboxOperation {
  final ConsumerId consumerId;
  final String? reason;
  final String consumerLabel;

  const IssueNoticeOperation({
    required super.clientUuid,
    required super.capturedAt,
    required this.consumerId,
    required this.consumerLabel,
    this.reason,
  });

  @override
  String get operationCode => 'issue_notice';

  @override
  Map<String, Object?> toPayloadJson() => <String, Object?>{
        'consumer_id': consumerId.value,
        'reason': reason,
        'consumer_label': consumerLabel,
      };

  @override
  String get description => 'Disconnection notice for $consumerLabel';

  @override
  Future<Result<String>> submit(OutboxGateway gateway) =>
      gateway.submitNotice(this);
}

/// How a queued operation reaches the server.
///
/// One method per subclass of [OutboxOperation]. The implementation lives in
/// `data/` and calls the matching Postgres function through `supabase.rpc`.
/// It never reimplements what those functions do: `fn_record_payment` settles
/// several bills in one transaction, and a Dart loop doing three updates is
/// not the same thing.
abstract class OutboxGateway {
  Future<Result<String>> submitReading(RecordReadingOperation operation);
  Future<Result<String>> submitPostedAmount(PostAmountOperation operation);
  Future<Result<String>> submitPayment(RecordPaymentOperation operation);
  Future<Result<String>> submitNotice(IssueNoticeOperation operation);
}
