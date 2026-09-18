import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/entities/app_user.dart';
import '../common/failure_banner.dart';
import '../providers.dart';
import 'app_lock_controller.dart';
import 'auth_controller.dart';
import 'forgot_password_sheet.dart';

/// GEN-01. The username here is what staff are given ("ledesman.dormal").
/// Turning it into the credential Supabase Auth wants happens in the data
/// layer, which is why this screen never mentions an email address.
///
/// The screen has two faces. Signed out, it is the username and password
/// form. When a session was restored on a phone where fingerprint sign-in is
/// on, it is the lock: the same screen, greeting the person by name, with the
/// phone's own screen lock as the way through. The router decides which, by
/// holding a locked session here; this screen only draws it.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  /// Text field contents and a spinner are screen state, not domain state,
  /// so they live here. Anything that is a fact about a household, a bill or
  /// a reading goes through a use case instead.
  AppFailure? _failure;
  bool _isSubmitting = false;
  bool _obscure = true;

  /// On the lock: the password field for the same account is showing in
  /// place of the fingerprint button.
  bool _passwordUnlock = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });
    ref.read(signInNoticeProvider.notifier).clear();

    final failure = await ref
        .read(authControllerProvider.notifier)
        .signIn(username: _username.text, password: _password.text);

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _failure = failure;
    });
    // On success the router notices the new user and moves. This screen does
    // not push a route, because where each role lands is the user's business.
  }

  /// The fingerprint button. The operating system shows the prompt and only
  /// answers yes or no; on yes the lock lifts and the router moves on.
  Future<void> _unlock() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });

    final failure = await ref.read(appLockControllerProvider.notifier).unlock();

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _failure = failure;
    });
  }

  /// The lock's password route, for the same account. The session is kept,
  /// so this works with no signal; see AppLockController.unlockWithPassword.
  Future<void> _unlockWithPassword(AppUser user) async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });

    final failure = await ref
        .read(appLockControllerProvider.notifier)
        .unlockWithPassword(user, _password.text);

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _failure = failure;
    });
    if (failure == null) _password.clear();
  }

  /// Somebody else using the phone: sign the locked session out and show the
  /// ordinary form. Readings still waiting to sync survive this — signing out
  /// keeps the outbox. With no signal nobody could sign back in afterwards,
  /// so that is said before it happens rather than discovered after.
  Future<void> _useDifferentAccount() async {
    if (_isSubmitting) return;
    if (!ref.read(networkStatusProvider).isOnline) {
      final bool? goAhead = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          title: const Text('You’re offline'),
          content: const Text(
            'Signing out now removes this account from the phone, and signing '
            'in again needs an internet connection. To keep using BillAlert '
            'offline, unlock with your fingerprint or password instead.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Stay on this account'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Sign out anyway'),
            ),
          ],
        ),
      );
      if (goAhead != true || !mounted) return;
    }
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });

    final failure = await ref.read(authControllerProvider.notifier).signOut();

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    final bool locked = ref.watch(appLockControllerProvider).locked;
    final AppUser? signedIn = ref.watch(authControllerProvider).value;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        '⚡',
                        style: TextStyle(fontSize: 30, height: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'BillAlert',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Bohol I Electric Cooperative',
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  if (locked && signedIn != null)
                    ..._unlockPanel(signedIn, textTheme, colorScheme)
                  else
                    ..._passwordForm(textTheme, colorScheme),
                  const SizedBox(height: 32),
                  Text(
                    'v1.0 · Bohol I Electric Cooperative',
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _passwordForm(
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) => <Widget>[
    // Why the app brought them here, when it did: for example after an
    // Area President reset the password and this phone was signed out.
    if (ref.watch(signInNoticeProvider) case final String notice) ...<Widget>[
      FailureBanner(failure: AuthFailure(notice)),
      const SizedBox(height: 16),
    ],
    Text('Username', style: textTheme.titleSmall),
    const SizedBox(height: 6),
    TextField(
      controller: _username,
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        // The mockup shows a real staff username here. A hint is only an
        // example, but printing a valid account on the sign-in screen
        // hands anyone holding the phone half of a login. The shape is
        // what the hint is for.
        hintText: 'firstname.lastname',
      ),
    ),
    const SizedBox(height: 16),
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text('Password', style: textTheme.titleSmall),
        // Was a GestureDetector with an empty handler: it did nothing, and
        // its hit area was the height of the text. A TextButton with the
        // padded tap target gives a thumb the 48px the Material and WCAG
        // guidance ask for.
        TextButton(
          onPressed: () => showForgotPasswordHelp(context),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: const Size(0, 40),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          child: Text('Forgot password?', style: textTheme.labelMedium),
        ),
      ],
    ),
    const SizedBox(height: 6),
    TextField(
      controller: _password,
      obscureText: _obscure,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _isSubmitting ? null : _submit(),
      decoration: InputDecoration(
        // The tooltip is what a screen reader announces: without it this
        // is an unlabelled button beside a field nobody can read.
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: colorScheme.onSurfaceVariant,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    ),
    if (_failure != null) ...<Widget>[
      const SizedBox(height: 16),
      FailureBanner(failure: _failure!),
    ],
    const SizedBox(height: 20),
    FilledButton(
      onPressed: _isSubmitting ? null : _submit,
      child: _isSubmitting
          ? SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onPrimary,
              ),
            )
          : const Text('Log in'),
    ),
    // No fingerprint button on this face. Signed out, there is no session
    // on the phone for a fingerprint to unlock, and the mockup's button
    // here did nothing at all. It appears on the other face — the lock —
    // where it works.
  ];

  List<Widget> _unlockPanel(
    AppUser user,
    TextTheme textTheme,
    ColorScheme colorScheme,
  ) => <Widget>[
    Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.fingerprint,
              size: 32,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Welcome back, ${user.firstName}',
            textAlign: TextAlign.center,
            style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'BillAlert is locked on this phone. Confirm it’s you to continue.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium,
          ),
        ],
      ),
    ),
    if (_failure != null) ...<Widget>[
      const SizedBox(height: 16),
      FailureBanner(failure: _failure!),
    ],
    const SizedBox(height: 20),
    if (_passwordUnlock) ...<Widget>[
      Text('Username', style: textTheme.titleSmall),
      const SizedBox(height: 6),
      // The account is fixed: this opens the session already on the phone,
      // it does not sign anybody else in.
      TextFormField(initialValue: user.username, enabled: false),
      const SizedBox(height: 16),
      Text('Password', style: textTheme.titleSmall),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey<String>('unlock-password'),
        controller: _password,
        obscureText: _obscure,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _unlockWithPassword(user),
        decoration: InputDecoration(
          suffixIcon: IconButton(
            tooltip: _obscure ? 'Show password' : 'Hide password',
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: colorScheme.onSurfaceVariant,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _isSubmitting ? null : () => _unlockWithPassword(user),
        child: _isSubmitting
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              )
            : const Text('Unlock'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _isSubmitting
            ? null
            : () => setState(() {
                _passwordUnlock = false;
                _failure = null;
                _password.clear();
              }),
        icon: const Icon(Icons.fingerprint, size: 20),
        label: const Text('Use fingerprint instead'),
      ),
    ] else ...<Widget>[
      FilledButton.icon(
        onPressed: _isSubmitting ? null : _unlock,
        icon: _isSubmitting
            ? SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.fingerprint, size: 22),
        label: const Text('Unlock with fingerprint'),
      ),
      const SizedBox(height: 8),
      Text(
        "Your fingerprint never leaves this device. Your phone's PIN works too.",
        textAlign: TextAlign.center,
        style: textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      TextButton(
        onPressed: _isSubmitting
            ? null
            : () => setState(() {
                _passwordUnlock = true;
                _failure = null;
              }),
        child: const Text('Use username and password'),
      ),
    ],
    const SizedBox(height: 4),
    TextButton(
      onPressed: _isSubmitting ? null : _useDifferentAccount,
      child: Text(
        'Sign in with a different account',
        style: textTheme.labelLarge?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  ];
}
