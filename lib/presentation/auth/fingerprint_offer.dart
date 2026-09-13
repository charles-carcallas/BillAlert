import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/app_user.dart';
import 'app_lock_controller.dart';
import 'auth_controller.dart';

/// Asks once, right after a password sign-in, whether to unlock with the
/// phone's screen lock next time.
///
/// It wraps every role's tab panels because that is the one place all four
/// roles reach after signing in — including after the forced password
/// change. It cannot be asked on the sign-in screen itself: by the time
/// sign-in succeeds, the router has already moved on.
class FingerprintOfferGate extends ConsumerStatefulWidget {
  final Widget child;

  const FingerprintOfferGate({required this.child, super.key});

  @override
  ConsumerState<FingerprintOfferGate> createState() =>
      _FingerprintOfferGateState();
}

class _FingerprintOfferGateState extends ConsumerState<FingerprintOfferGate> {
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    // Usually the offer is already waiting when this first appears: sign-in
    // settles it before the router opens the home screen. A listener alone
    // would never hear about a value that was set before it existed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _askIfOffered());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      appLockControllerProvider.select((AppLockState s) => s.offerFingerprint),
      (bool? _, bool offered) {
        if (offered) _askIfOffered();
      },
    );
    return widget.child;
  }

  Future<void> _askIfOffered() async {
    if (!mounted || _asking) return;
    if (!ref.read(appLockControllerProvider).offerFingerprint) return;
    final AppUser? user = ref.read(authControllerProvider).value;
    if (user == null) return;

    _asking = true;
    final bool? useIt = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        icon: const Icon(Icons.fingerprint, size: 32),
        title: const Text('Use your fingerprint next time?'),
        content: const Text(
          'Next time you open BillAlert on this phone, unlock it with your '
          "fingerprint or your phone's PIN instead of typing your password. "
          'Your fingerprint never leaves this device.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Use fingerprint'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    final AppLockController lock = ref.read(appLockControllerProvider.notifier);
    if (useIt ?? false) {
      final failure = await lock.turnOnFor(user);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure == null
                  ? 'Fingerprint sign-in is on for this phone.'
                  : failure.message,
            ),
          ),
        );
      }
    } else {
      await lock.declineOffer(user);
    }
    _asking = false;
  }
}
