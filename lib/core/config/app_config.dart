/// Every compile-time setting the app needs, read in exactly one place.
///
/// The Supabase URL and anon key are passed with `--dart-define` at build
/// time. They are never written into a tracked file, because anyone with the
/// repository would then have them:
///
/// ```
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGci...
/// ```
///
/// `String.fromEnvironment` must be read from a `const` context, which is why
/// these are `static const` fields and not getters that build a string.
class AppConfig {
  const AppConfig._();

  /// The Supabase project URL, e.g. https://abcdefgh.supabase.co
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// The Supabase anon key. Public by design — Row-Level Security, not this
  /// key, is what stops one area's reader seeing another area's consumers.
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Supabase Auth signs in with an email, but the login screen shows a
  /// username ("ledesman.dormal"). The app appends this domain to make the
  /// synthetic email the account was created with.
  static const String loginEmailDomain =
      String.fromEnvironment('LOGIN_EMAIL_DOMAIN', defaultValue: 'billalert.local');

  /// True when the app was built with both Supabase values supplied.
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// Shown instead of the login screen when someone runs a build without the
  /// dart-defines, which is the most common first-run mistake.
  static const String missingConfigMessage =
      'This build has no Supabase settings. Run the app with '
      '--dart-define=SUPABASE_URL=... and '
      '--dart-define=SUPABASE_ANON_KEY=... (see README.md).';

  /// Turns "ledesman.dormal" into the email Supabase Auth expects.
  static String emailForUsername(String username) =>
      '${username.trim().toLowerCase()}@$loginEmailDomain';
}
