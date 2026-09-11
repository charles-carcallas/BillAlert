import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/app_config.dart';
import '../../core/errors/app_failure.dart';
import '../common/failure_banner.dart';
import 'auth_controller.dart';

/// GEN-01. The username here is what staff are given ("ledesman.dormal").
/// Turning it into the credential Supabase Auth wants happens in the data
/// layer, which is why this screen never mentions an email address.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

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
                  if (AppConfig.demoMode) ...<Widget>[
                    const SizedBox(height: 16),
                    Card(
                      color: colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Demo data · Username: admin, reader, cashier, or '
                          'consumer · Password: demo',
                          textAlign: TextAlign.center,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text('Username', style: textTheme.titleSmall),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _username,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      // The mockup shows a real staff username here. A hint is
                      // only an example, but printing a valid account on the
                      // sign-in screen hands anyone holding the phone half of
                      // a login. The shape is what the hint is for.
                      hintText: 'firstname.lastname',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text('Password', style: textTheme.titleSmall),
                      GestureDetector(
                        onTap: () {},
                        child: Text(
                          'Forgot password?',
                          style: textTheme.labelMedium,
                        ),
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
                      suffixIcon: IconButton(
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
                  const SizedBox(height: 24),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('or', style: textTheme.bodySmall),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.fingerprint, size: 22),
                    label: const Text('Unlock with fingerprint'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "For devices you've signed in on before. Your fingerprint never leaves this device.",
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall,
                  ),
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
}
