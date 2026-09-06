/// Typed identifiers.
///
/// Every id in the database is a `uuid`, so in Dart they would all be
/// `String` and nothing would stop you passing a bill id where a consumer id
/// belongs — the compiler cannot tell two strings apart. Wrapping each one in
/// its own type makes that mistake impossible to write.
///
/// [Identifier] exists for one reason worth defending: the `==` below
/// compares `runtimeType` as well as the value, so `ConsumerId('abc')` is not
/// equal to `BillId('abc')`. That is shared *behaviour*, not just a shared
/// field, and every subclass gets it for free.
abstract class Identifier {
  final String value;

  const Identifier(this.value);

  @override
  bool operator ==(Object other) =>
      other is Identifier &&
      other.runtimeType == runtimeType &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => value;
}

/// `profiles.id` — also the Supabase Auth user id.
final class ProfileId extends Identifier {
  const ProfileId(super.value);
}

/// `areas.id` — one of the four service areas of Barangay Tubod.
final class AreaId extends Identifier {
  const AreaId(super.value);
}

/// `consumers.id`
final class ConsumerId extends Identifier {
  const ConsumerId(super.value);
}

/// `bills.id`
final class BillId extends Identifier {
  const BillId(super.value);
}

/// `meter_readings.id`
final class ReadingId extends Identifier {
  const ReadingId(super.value);
}

/// `payment_transactions.id`
final class TransactionId extends Identifier {
  const TransactionId(super.value);
}

/// `disconnection_notices.id`
final class NoticeId extends Identifier {
  const NoticeId(super.value);
}

/// `notifications.id`
final class NotificationId extends Identifier {
  const NotificationId(super.value);
}

/// The idempotency key minted on the device and sent to the server.
///
/// It is generated once, when a queued action is created, and never again on
/// retry. That is the whole reason a sync that times out and runs a second
/// time cannot create two readings: `fn_record_meter_reading` looks up this
/// value first and returns the original bill.
final class ClientUuid extends Identifier {
  const ClientUuid(super.value);
}

/// Makes a fresh [ClientUuid]. Injected so tests can hand out predictable
/// ids without the domain layer depending on a uuid package.
typedef ClientUuidFactory = ClientUuid Function();

/// `bills.bill_no` — "BA-202609-000123". A human-facing number, not a uuid.
final class BillNumber {
  final String value;

  const BillNumber(this.value);

  @override
  bool operator ==(Object other) => other is BillNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// `consumers.consumer_no` — "2019-0917-TUB", the number on the bill.
final class ConsumerNumber {
  final String value;

  const ConsumerNumber(this.value);

  @override
  bool operator ==(Object other) =>
      other is ConsumerNumber && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
