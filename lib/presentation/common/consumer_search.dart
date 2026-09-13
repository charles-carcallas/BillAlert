// `Consumer` here means a household.
import '../../domain/entities/consumer.dart';

/// Matches the identifying facts a field worker can know or see at a meter.
bool consumerMatchesSearch(Consumer consumer, String rawQuery) {
  final String query = rawQuery.trim().toLowerCase();
  if (query.isEmpty) return true;

  return <String>[
    consumer.fullName,
    consumer.consumerNo.value,
    if (consumer.purok != null) consumer.purok!,
    if (consumer.meterSerialNo != null) consumer.meterSerialNo!,
  ].any((String value) => value.toLowerCase().contains(query));
}
