/// What went wrong, expressed as a value the app can carry around.
///
/// Every failure holds a [message] written for a meter reader, a cashier or
/// a consumer — never a database error string. The technical cause goes in
/// [debugDetail], which is logged, but is never rendered on a screen a user
/// sees. "Could not reach the server, your reading is saved" is the product;
/// `PostgrestException(code: 23505)` is a bug report that leaked.
///
/// The hierarchy is sealed, so a `switch` over a failure is exhaustive and
/// the compiler points at every place that must handle a new kind.
sealed class AppFailure {
  /// Plain English. Safe to put straight on the screen.
  final String message;

  /// The raw cause — a Postgres error code, an exception string. Never shown.
  final String? debugDetail;

  const AppFailure(this.message, [this.debugDetail]);

  @override
  String toString() =>
      '$runtimeType($message)${debugDetail == null ? '' : ' <- $debugDetail'}';
}

/// The phone could not reach the server. In BillAlert this is ordinary, not
/// exceptional: the meter reader works with no signal for hours at a time.
final class NetworkFailure extends AppFailure {
  static const String defaultMessage =
      'No connection right now. Your work is saved on this phone and will '
      'sync by itself when you are back in signal.';

  const NetworkFailure([super.message = defaultMessage, super.debugDetail]);
}

/// Not signed in, wrong password, or the session expired.
final class AuthFailure extends AppFailure {
  static const String defaultMessage =
      'Your username or password is incorrect.';

  const AuthFailure([super.message = defaultMessage, super.debugDetail]);
}

/// The server refused because of who the user is: Row-Level Security blocked
/// the row. A meter reader reaching outside their service area lands here.
final class PermissionFailure extends AppFailure {
  static const String defaultMessage =
      'You do not have access to this record. It may belong to another '
      'service area.';

  const PermissionFailure([super.message = defaultMessage, super.debugDetail]);
}

/// The input does not make sense — an empty field, a reading below the
/// previous one, an amount that is not a number.
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, [super.debugDetail]);
}

/// The action clashes with something already recorded. FR-23 lives here:
/// this consumer has already been read for this billing cycle.
final class ConflictFailure extends AppFailure {
  const ConflictFailure(super.message, [super.debugDetail]);
}

/// Anything else the server did not handle. The catch-all, deliberately last.
final class ServerFailure extends AppFailure {
  static const String defaultMessage =
      'Something went wrong on the server. Please try again in a moment.';

  const ServerFailure([super.message = defaultMessage, super.debugDetail]);
}
