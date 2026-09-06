import 'package:drift/drift.dart';

import '../../domain/entities/consumer.dart';
import '../../domain/value_objects/cycle_label.dart';
import '../../domain/value_objects/ids.dart';
import '../../domain/value_objects/kwh.dart';
import '../../domain/value_objects/ph_date.dart';
import '../local/app_database.dart';

/// Translation between a household as the database stores it and the
/// [Consumer] the domain layer works with.
///
/// Both directions live here so there is one place to look when a column is
/// added. Note that every numeric value crosses through a String on the way
/// in: PostgREST sends a `numeric` column as a JSON number, which Dart
/// decodes as a `double`, and a reading must not pass through one. Going via
/// `toString()` keeps the exact decimal digits the database sent.
class ConsumerDto {
  const ConsumerDto._();

  /// A row of the encrypted cache, turned into a domain entity.
  static Consumer fromCacheRow(CachedConsumerRow row) => Consumer(
        id: ConsumerId(row.id),
        consumerNo: ConsumerNumber(row.consumerNo),
        firstName: row.firstName,
        lastName: row.lastName,
        contactNumber: row.contactNumber,
        meterSerialNo: row.meterSerialNo,
        areaId: AreaId(row.areaId),
        purok: row.purok,
        accountStatus: AccountStatus.fromCode(row.accountStatus),
        previousReading: Kwh.fromHundredths(row.previousReadingHundredths),
        previousReadingDate: row.previousReadingDate == null
            ? null
            : PhDate.tryParse(row.previousReadingDate!),
        lastReadCycle: row.lastReadCycle == null
            ? null
            : CycleLabel.tryParse(row.lastReadCycle!),
      );

  /// A `consumers` row from Supabase, plus the latest reading found for it,
  /// ready to be written into the cache.
  static CachedConsumersCompanion toCacheRow({
    required Map<String, dynamic> json,
    required Kwh previousReading,
    required String? previousReadingDate,
    required String? lastReadCycle,
  }) =>
      CachedConsumersCompanion.insert(
        id: json['id'] as String,
        consumerNo: json['consumer_no'] as String,
        firstName: json['first_name'] as String,
        lastName: json['last_name'] as String,
        contactNumber: Value<String?>(json['contact_number'] as String?),
        meterSerialNo: Value<String?>(json['meter_serial_no'] as String?),
        areaId: json['area_id'] as String,
        purok: Value<String?>(json['purok'] as String?),
        accountStatus: json['account_status'] as String,
        previousReadingHundredths: Value<int>(previousReading.hundredths),
        previousReadingDate: Value<String?>(previousReadingDate),
        lastReadCycle: Value<String?>(lastReadCycle),
        updatedAt: Value<String?>(DateTime.now().toUtc().toIso8601String()),
      );

  /// Reads a `numeric` column without ever building a double from it.
  static Kwh kwhFrom(Object? value) {
    if (value == null) return Kwh.zero;
    return Kwh.tryParse(value.toString()) ?? Kwh.zero;
  }
}
