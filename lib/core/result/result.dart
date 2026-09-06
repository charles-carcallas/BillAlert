import '../errors/app_failure.dart';

/// The outcome of something that can fail: either [Ok] with a value, or
/// [Err] with an [AppFailure].
///
/// Why not throw? Because an exception can be forgotten. A `Result` is in the
/// return type, so the compiler forces every caller to say what happens when
/// the operation fails — and every layer boundary in BillAlert crosses a
/// network or a database, which fail routinely.
///
/// Use it with a switch:
///
/// ```dart
/// switch (await recordReading(consumerId: id, currentReading: kwh)) {
///   case Ok(:final value):   showSaved(value);
///   case Err(:final failure): showMessage(failure.message);
/// }
/// ```
sealed class Result<T> {
  const Result();
}

/// It worked, and here is the value.
final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

/// It failed, and here is why — in words a user can read.
final class Err<T> extends Result<T> {
  final AppFailure failure;
  const Err(this.failure);
}
