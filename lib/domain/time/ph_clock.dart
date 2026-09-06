import '../value_objects/ph_date.dart';

/// Tells the app what time it is, in Philippine terms.
///
/// It is an interface rather than a call to `DateTime.now()` for one
/// practical reason: "has this consumer already been read this cycle?"
/// changes answer on the first of the month, and a test that can only run
/// correctly on certain days of the year is not a test.
abstract class PhClock {
  /// The current instant, in UTC. This is what is sent to the server as
  /// `captured_at` — the moment of capture, not the moment of sync.
  DateTime nowUtc();

  /// Today's date in Asia/Manila.
  PhDate today();
}

/// The real clock. Reads the device time but immediately converts it, so a
/// phone set to the wrong timezone still files readings into the correct
/// Philippine cycle.
final class SystemPhClock implements PhClock {
  const SystemPhClock();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  PhDate today() => PhDate.at(DateTime.now());
}
