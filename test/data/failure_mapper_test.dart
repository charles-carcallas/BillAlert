import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/data/supabase/failure_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The rubric marks plain-English errors explicitly, and this is where they
/// are decided. These tests exist because one wrong branch here told a
/// signed-in user they had been signed out.
void main() {
  group('changing a password', () {
    test('the same password again is a validation problem, not a lost session',
        () {
      // Captured from the live project: PUT /auth/v1/user with the current
      // password returns 422 same_password.
      final failure = FailureMapper.from(
        const AuthException(
          'New password should be different from the old password.',
          statusCode: '422',
          code: 'same_password',
        ),
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('different'));
      // The bug: this said "You have been signed out. Please sign in again."
      // to somebody who was still signed in, on the one screen they could not
      // leave. It sent them round a loop with no way through.
      expect(failure.message, isNot(contains('signed out')));
    });

    test('a password the server considers weak says so', () {
      final failure = FailureMapper.from(
        const AuthException(
          'Password should be at least 6 characters.',
          statusCode: '422',
          code: 'weak_password',
        ),
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure.message, isNot(contains('signed out')));
    });

    test('an unnamed 422 is still not a lost session', () {
      // Whatever GoTrue adds next, a 422 is about what was typed.
      final failure = FailureMapper.from(
        const AuthException('Something the app has not seen before.',
            statusCode: '422'),
      );

      expect(failure.message, isNot(contains('signed out')));
    });

    test('the prose form is caught too, for a server that sends no code', () {
      final failure = FailureMapper.from(
        const AuthException(
          'New password should be different from the old password.',
        ),
      );

      expect(failure, isA<ValidationFailure>());
    });
  });

  group('signing in', () {
    test('wrong credentials are reported as wrong credentials', () {
      final byCode = FailureMapper.from(
        const AuthException('Invalid login credentials',
            statusCode: '400', code: 'invalid_credentials'),
      );
      final byProse =
          FailureMapper.from(const AuthException('Invalid login credentials'));

      for (final AppFailure failure in <AppFailure>[byCode, byProse]) {
        expect(failure, isA<AuthFailure>());
        expect(failure.message, contains('not correct'));
      }
    });

    test('an unactivated account is told to ask the Area President', () {
      final failure = FailureMapper.from(
        const AuthException('Email not confirmed', statusCode: '400'),
      );

      expect(failure, isA<AuthFailure>());
      expect(failure.message, contains('Area President'));
    });
  });

  group('no signal', () {
    test('a lost connection during sign-in is a network failure, not a server one',
        () {
      // gotrue catches the transport failure and rethrows it as an
      // AuthException subclass, so the SocketException check never sees it.
      // Before this was handled, a meter reader with no signal was told the
      // server was broken - on an app built to work without signal.
      final failure = FailureMapper.from(
        AuthRetryableFetchException(message: 'Failed host lookup'),
      );

      expect(failure, isA<NetworkFailure>());
      expect(failure.message, contains('No connection'));
      expect(failure.message, isNot(contains('server')));
    });
  });

  group('a session that really has ended', () {
    test('401 says so', () {
      final failure = FailureMapper.from(
        const AuthException('JWT expired', statusCode: '401'),
      );

      expect(failure, isA<AuthFailure>());
      expect(failure.message, contains('signed out'));
    });

    test('403 says so', () {
      final failure = FailureMapper.from(
        const AuthException('Forbidden', statusCode: '403'),
      );

      expect(failure.message, contains('signed out'));
    });
  });

  group('the technical cause is kept but never shown', () {
    test('the raw message goes to debugDetail, not to the screen', () {
      final failure = FailureMapper.from(
        const AuthException('New password should be different from the old '
            'password.', statusCode: '422', code: 'same_password'),
      );

      expect(failure.debugDetail, isNotNull);
      expect(failure.debugDetail, contains('AuthException'));
      // Nothing a user reads should carry the server's own wording.
      expect(failure.message, isNot(contains('AuthException')));
    });
  });
}
