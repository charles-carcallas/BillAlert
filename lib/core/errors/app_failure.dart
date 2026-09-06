/// What went wrong, expressed as a value the app can carry around.
///
/// Every failure holds a [message] written for a meter reader, a cashier or
/// a consumer — never a database error string. The technical cause goes in
/// [debugDetail], which is logged and shown in debug builds, but never
/// rendered on a screen a user sees.
///
/// The hierarchy is sealed, so a `switch` over a failure is exhaustive and
/// the compiler tells you when a new kind of failure is added.
sealed class AppFailure {
  /// Plain English. Safe to put straight on the screen.
  final String message;

  /// The raw cause (a Postgres error code, an exception string). Never shown.
  final String? debugDetail;

  const AppFailure(this.message, {this.debugDetail});

  @override
  String toString() => '$runtimeType($message)'
      '${debugDetail == null ? '' : ' <- $debugDetail'}';
}

/// The phone could not reach the server. In BillAlert this is normal, not
/// exceptional: the meter reader works with no signal for hours at a time.
final class NetworkFailure extends AppFailure {
  const NetworkFailure([
    String message =
        'No connection right now. Your work is saved on this phone and will '
        'sync by itself when you are back in signal.',
    String? debugDetail,
  ]) : super(message, debugDetail: debugDetail);
}

/// The user is not signed in, the password is wrong, or the session expired.
final class AuthFailure extends AppFailure {
  const AuthFailure([
    String message = 'Your username or password is incorrect.',
    String? debugDetail,
  ]) : super(message, debugDetail: debugDetail);
}

/// The server refused because of who the user is: Row-Level Security blocked
/// the row. A meter reader reaching outside their service area lands here.
final class PermissionFailure extends AppFailure {
  const PermissionFailure([
    String message =
        'You do not have access to this record. It may belong to another '
        'service area.',
    String? debugDetail,
  ]) : super(message, debugDetail: debugDetail);
}

/// The input does not make sense — an empty field, a reading below the
/// previous one, an amount that is not a number.
final class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.debugDetail});
}

/// The action clashes with something already recorded. FR-23 lives here:
/// this consumer has already been read for this billing cycle.
final class ConflictFailure extends AppFailure {
  const ConflictFailure(super.message, {super.debugDetail});
}

/// Anything else the server did not handle. The catch-all, deliberately last.
final class ServerFailure extends AppFailure {
  const ServerFailure([
    String message =
        'Something went wrong on the server. Please try again in a moment.',
    String? debugDetail,
  ]) : super(message, debugDetail: debugDetail);
}
