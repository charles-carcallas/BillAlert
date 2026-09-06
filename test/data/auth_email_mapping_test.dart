import 'package:billalert/core/config/app_config.dart';
import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/data/repositories/auth_repository_impl.dart';
import 'package:billalert/data/supabase/failure_mapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Staff are given a username. Supabase Auth wants an email. This is the seam
/// between those two facts, and the only place in the app that knows about it.
///
/// No SupabaseClient is constructed here: the mapping is a pure function of a
/// string, which is why it can be tested at all.
void main() {
  group('username to email', () {
    test('appends the configured domain', () {
      expect(
        AuthRepositoryImpl.emailForUsername('ledesman.dormal'),
        'ledesman.dormal@billalert.local',
      );
    });

    test('uses the named constant rather than a hardcoded suffix', () {
      // If someone builds with --dart-define=LOGIN_EMAIL_DOMAIN=..., the
      // mapping has to follow it. Asserting against the constant rather than
      // the literal is what makes that true.
      expect(
        AuthRepositoryImpl.emailForUsername('ledesman.dormal'),
        'ledesman.dormal@${AppConfig.loginEmailDomain}',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        AuthRepositoryImpl.emailForUsername('  ledesman.dormal  '),
        'ledesman.dormal@billalert.local',
      );
    });

    test('lowercases the username', () {
      expect(
        AuthRepositoryImpl.emailForUsername('Ledesman.Dormal'),
        'ledesman.dormal@billalert.local',
      );
      expect(
        AuthRepositoryImpl.emailForUsername('LEDESMAN.DORMAL'),
        'ledesman.dormal@billalert.local',
      );
    });

    test('a username typed on a phone keyboard still signs in', () {
      // Leading capital from autocapitalise, trailing space from the spacebar.
      // Both are ordinary, and neither should look like a different account.
      expect(
        AuthRepositoryImpl.emailForUsername(' Ledesman.Dormal '),
        'ledesman.dormal@billalert.local',
      );
    });

    test('a tab or newline pasted in is trimmed too', () {
      expect(
        AuthRepositoryImpl.emailForUsername('\tledesman.dormal\n'),
        'ledesman.dormal@billalert.local',
      );
    });

    test('two spellings of the same name map to one account', () {
      expect(
        AuthRepositoryImpl.emailForUsername(' Ledesman.Dormal '),
        AuthRepositoryImpl.emailForUsername('ledesman.dormal'),
      );
    });
  });

  group('the synthetic email never reaches the user', () {
    /// The person signing in has never been shown an email address, so an
    /// error quoting one would be describing something they have never seen.
    /// Every AuthException message is replaced with wording of our own; the
    /// server's text goes to debugDetail, which FailureBanner does not render.
    void expectNoEmailIn(AppFailure failure) {
      expect(
        failure.message,
        isNot(contains('@')),
        reason: 'message shown to the user leaked an address',
      );
      expect(failure.message, isNot(contains('billalert.local')));
    }

    test('wrong password gives the username-or-password wording', () {
      final failure = FailureMapper.from(
        const AuthException('Invalid login credentials'),
      );

      expect(failure, isA<AuthFailure>());
      expect(
        failure.message,
        'That username or password is not correct. Please try again.',
      );
      expectNoEmailIn(failure);
    });

    test('an unactivated account says so without quoting an address', () {
      final failure = FailureMapper.from(
        const AuthException('Email not confirmed'),
      );

      expect(failure.message, contains('not been activated'));
      expectNoEmailIn(failure);
    });

    test('even a server message containing the address does not leak it', () {
      // The wording Supabase sends is not shown, whatever it happens to be.
      final failure = FailureMapper.from(
        const AuthException('User ledesman.dormal@billalert.local not found'),
      );

      expectNoEmailIn(failure);
      // It is kept for the log, where it is useful and nobody is misled by it.
      expect(failure.debugDetail, contains('billalert.local'));
    });
  });
}
