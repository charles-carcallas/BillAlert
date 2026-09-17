import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../common/failure_banner.dart';
import 'auth_controller.dart';

/// GEN-04. A new account is issued a temporary password and cannot reach
/// anything else until it is replaced. The router enforces that; this screen
/// only has to do the replacing.
///
/// It serves two arrivals, and the difference is worth knowing:
///
/// - **Forced**, at `/change-password`, when `mustChangePassword` is set. The
///   router pins the user here and there is no way on but succeeding. When
///   they do, the auth state changes, the redirect fires, and this screen is
///   gone before it could show anything.
/// - **Voluntary**, at `/account/password`, pushed from the Profile tab. No
///   redirect will move them, so here the screen has to say it worked and
///   give them a way back.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  AppFailure? _failure;
  bool _isSubmitting = false;

  /// Each field hides itself until asked. Separately, because revealing the
  /// password you are choosing is a different decision from revealing the
  /// one you are typing back to confirm it — and a single switch that
  /// uncovered both would make the confirmation a copy rather than a check.
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// Only ever seen on the voluntary path. The forced one is redirected away
  /// the instant the password changes, so it never renders this.
  bool _succeeded = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _failure = null;
    });

    final failure = await ref
        .read(authControllerProvider.notifier)
        .changePassword(
          newPassword: _password.text,
          confirmPassword: _confirm.text,
        );

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _failure = failure;
      _succeeded = failure == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;
    final bool forced = user?.mustChangePassword ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change your password'),
        // No back arrow while it is compulsory: there is nowhere to go back to.
        automaticallyImplyLeading: !forced,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _succeeded
              ? _Changed(onDone: () => Navigator.of(context).maybePop())
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      user == null
                          ? 'Please choose a new password.'
                          : forced
                          ? 'Welcome, ${user.firstName}. You signed in '
                                'with a temporary password from your Area '
                                'President. Please choose your own password '
                                'before you continue.'
                          : 'Choose a new password for your account.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    _PasswordField(
                      controller: _password,
                      label: 'New password',
                      obscured: _obscurePassword,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      action: TextInputAction.next,
                    ),
                    const SizedBox(height: 16),
                    _PasswordField(
                      controller: _confirm,
                      label: 'Type it again',
                      obscured: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      action: TextInputAction.done,
                      onSubmitted: _isSubmitting ? null : _submit,
                    ),
                    if (_failure != null) ...<Widget>[
                      const SizedBox(height: 16),
                      FailureBanner(failure: _failure!),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: const Text('Save new password'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// A password box with the eye that uncovers it.
///
/// Choosing a password you cannot see is guesswork, and this screen asks for
/// one twice before it will let anyone past — so a household that mistypes
/// has no way to find out which of the two boxes was wrong. The eye is what
/// makes that recoverable.
///
/// The icon says what tapping it will do, not what the field is doing now:
/// a covered field offers the open eye. That is the same way round as the
/// sign-in screen, and the tooltip says it in words for a screen reader.
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscured;
  final VoidCallback onToggle;
  final TextInputAction action;
  final VoidCallback? onSubmitted;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscured,
    required this.onToggle,
    required this.action,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colours = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      obscureText: obscured,
      textInputAction: action,
      onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: obscured ? 'Show $label' : 'Hide $label',
          icon: Icon(
            obscured
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: colours.onSurfaceVariant,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }
}

/// The voluntary path's ending. The forced path never reaches it — the router
/// has already moved on by the time the password has changed.
class _Changed extends StatelessWidget {
  final VoidCallback onDone;

  const _Changed({required this.onDone});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 24),
        Icon(
          Icons.check_circle_outline,
          size: 44,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Password changed',
          style: text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Use the new password the next time you sign in. You are still '
          'signed in on this device.',
          style: text.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ],
    );
  }
}
