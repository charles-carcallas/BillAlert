import '../value_objects/cycle_label.dart';
import '../value_objects/ids.dart';
import '../value_objects/kwh.dart';
import '../value_objects/ph_date.dart';

/// `consumers.account_status` / `profiles.account_status`.
enum AccountStatus {
  pending,
  active,
  inactive;

  /// Reads the value as the database spells it.
  static AccountStatus fromCode(String code) {
    switch (code) {
      case 'active':
        return AccountStatus.active;
      case 'inactive':
        return AccountStatus.inactive;
      default:
        return AccountStatus.pending;
    }
  }

  String get code => name;
}

/// A household on the meter reader's roster.
///
/// [previousReading] and [lastReadCycle] are denormalised onto this entity on
/// purpose. The reader is standing at a meter in a barangay with no signal;
/// everything needed to judge the reading they just typed has to already be
/// on the phone.
final class Consumer {
  final ConsumerId id;
  final ConsumerNumber consumerNo;
  final String firstName;
  final String lastName;
  final String? contactNumber;
  final String? meterSerialNo;
  final AreaId areaId;
  final String? purok;
  final AccountStatus accountStatus;

  /// MTR-08: last cycle's reading, or zero for a brand new meter.
  final Kwh previousReading;
  final PhDate? previousReadingDate;

  /// The last cycle this consumer was read for, if any.
  final CycleLabel? lastReadCycle;

  const Consumer({
    required this.id,
    required this.consumerNo,
    required this.firstName,
    required this.lastName,
    required this.areaId,
    required this.accountStatus,
    required this.previousReading,
    this.contactNumber,
    this.meterSerialNo,
    this.purok,
    this.previousReadingDate,
    this.lastReadCycle,
  });

  String get fullName => '$firstName $lastName';

  /// An inactive or pending account is not read and not billed.
  bool get isActive => accountStatus == AccountStatus.active;

  /// FR-23: already read for this cycle, according to what synced down.
  /// The outbox is checked separately, for work that has not synced up yet.
  bool hasBeenReadFor(CycleLabel cycle) => lastReadCycle == cycle;

  /// MTR-08: a meter does not run backwards, so a present reading below the
  /// previous one is a mistyped digit. The server refuses it too — this is
  /// the copy that catches it while the reader is still at the meter.
  bool isPlausibleReading(Kwh current) => current >= previousReading;

  /// Energy used since the last reading. kWh, not pesos.
  Kwh consumptionFor(Kwh current) => current - previousReading;
}
