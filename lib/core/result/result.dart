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

/// For work only the server can do, which is never kept to sync later:
/// creating an account or a household, resetting or changing a password.
///
/// A reading or a payment made without signal waits in the outbox, and the
/// app's general offline message says so: "your work is saved on this phone
/// and will sync". For these it is untrue. Nothing was saved, and a person
/// who believes otherwise walks away thinking an account exists. [message]
/// replaces it, and should say that nothing happened.
extension ServerOnlyResult<T> on Result<T> {
  Result<T> ifOffline(String message) => switch (this) {
    Err<T>(:final NetworkFailure failure) => Err<T>(
      NetworkFailure(message, failure.debugDetail),
    ),
    _ => this,
  };
}
