import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import 'network_error.dart';

/// Turns whatever Supabase threw into an [AppFailure] a person can read.
///
/// This is the only place in the app allowed to know what a
/// `PostgrestException` is. Everywhere else deals in AppFailure, which is why
/// no screen can accidentally render `PostgrestException(code: 23505)` — the
/// rubric marks that down, and rightly.
///
/// If a new error needs handling, it is handled here and nowhere else.
class FailureMapper {
  const FailureMapper._();

  /// SQLSTATE 23505: a unique constraint. FR-23 arrives as this when two
  /// readings for the same consumer and cycle race each other.
  static const String _uniqueViolation = '23505';

  /// SQLSTATE P0002: `no_data_found`, raised when a consumer is not visible.
  static const String _noDataFound = 'P0002';

  /// SQLSTATE P0001: a plain `raise exception` in one of our own functions.
  /// Those messages are written for people, so they are passed through.
  static const String _raisedException = 'P0001';

  /// SQLSTATE 42501: insufficient privilege — Row-Level Security refused.
  static const String _insufficientPrivilege = '42501';

  static AppFailure from(Object error, [StackTrace? stackTrace]) {
    final detail = error.toString();

    // ---- no network -------------------------------------------------
    // Ordinary in the field, so it gets the reassuring message rather than
    // an alarming one. What counts as a network error differs between a
    // phone and a browser, which is why the check is behind a conditional
    // import rather than a `dart:io` type test written here.
    if (isNetworkError(error)) {
      return NetworkFailure(NetworkFailure.defaultMessage, detail);
    }

    // ---- authentication --------------------------------------------
    if (error is AuthException) {
      final message = error.message.toLowerCase();
      if (message.contains('invalid login credentials')) {
        return AuthFailure(
          'That username or password is not correct. Please try again.',
          detail,
        );
      }
      if (message.contains('email not confirmed')) {
        return AuthFailure(
          'This account has not been activated yet. Ask your Area President '
          'to activate it.',
          detail,
        );
      }
      return AuthFailure(
        'You have been signed out. Please sign in again.',
        detail,
      );
    }

    // ---- the database ----------------------------------------------
    if (error is PostgrestException) {
      return _fromPostgrest(error, detail);
    }

    if (error is StorageException) {
      return ServerFailure(ServerFailure.defaultMessage, detail);
    }

    return ServerFailure(ServerFailure.defaultMessage, detail);
  }

  static AppFailure _fromPostgrest(PostgrestException error, String detail) {
    final code = error.code;

    // PostgREST's own codes come through as PGRSTxxx rather than SQLSTATE.
    if (code != null && code.startsWith('PGRST')) {
      if (code == 'PGRST301' || code == 'PGRST302') {
        return AuthFailure(
          'Your session has expired. Please sign in again.',
          detail,
        );
      }
      return ServerFailure(ServerFailure.defaultMessage, detail);
    }

    switch (code) {
      case _uniqueViolation:
        // The function raises a sentence naming the consumer and the month.
        return ConflictFailure(_humanise(error.message), detail);

      case _noDataFound:
        return ValidationFailure(
          'That record could not be found. It may have been changed by '
          'someone else, or it may belong to another service area.',
          detail,
        );

      case _raisedException:
        // Our own functions raise messages written for people —
        // "Consumer 2019-0917-TUB is not active". Passed through on purpose.
        // This holds only as long as 02_functions.sql keeps those messages
        // readable, which is worth remembering before editing them.
        return ValidationFailure(_humanise(error.message), detail);

      case _insufficientPrivilege:
        return PermissionFailure(PermissionFailure.defaultMessage, detail);

      default:
        // A foreign key or check constraint that got past the app's own
        // validation. The user cannot act on the detail, so they do not see
        // it — but it is logged.
        if (code != null && code.startsWith('23')) {
          return ValidationFailure(
            'That information does not fit what the system expects. Please '
            'check the details and try again.',
            detail,
          );
        }
        return ServerFailure(ServerFailure.defaultMessage, detail);
    }
  }

  /// Tidies a raised message: first letter capitalised, one trailing stop.
  static String _humanise(String raw) {
    var text = raw.trim();
    if (text.isEmpty) {
      return ServerFailure.defaultMessage;
    }
    text = text[0].toUpperCase() + text.substring(1);
    if (!text.endsWith('.') && !text.endsWith('!') && !text.endsWith('?')) {
      text = '$text.';
    }
    return text;
  }
}
