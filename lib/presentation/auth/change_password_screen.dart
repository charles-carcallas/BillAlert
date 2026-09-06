import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_failure.dart';
import '../common/failure_banner.dart';
import 'auth_controller.dart';

/// GEN-04. A new account is issued a temporary password and cannot reach
/// anything else until it is replaced. The router enforces that; this screen
/// only has to do the replacing.
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

    final failure =
        await ref.read(authControllerProvider.notifier).changePassword(
              newPassword: _password.text,
              confirmPassword: _confirm.text,
            );

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _failure = failure;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Change your password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                user == null
                    ? 'Please choose a new password.'
                    : 'Welcome, ${user.firstName}. Please choose a new '
                        'password before you continue.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirm,
                obscureText: true,
                decoration:
                    const InputDecoration(labelText: 'Type it again'),
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
