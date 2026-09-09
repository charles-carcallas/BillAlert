import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../auth/auth_controller.dart';
import '../providers.dart';
import '../router.dart';

/// Work the app is holding that has not reached the server yet.
///
/// Read here rather than passed in, so the number on the Profile screen is
/// the outbox's own answer and cannot drift from it.
final pendingOutboxProvider = FutureProvider<List<OutboxEntry>>((Ref ref) async {
  final result = await ref.watch(outboxRepositoryProvider).pending();
  return switch (result) {
    Ok(:final value) => value,
    // A queue that cannot be read is reported as empty rather than as an
    // error: the Profile screen's job is signing out, and it must not become
    // unusable because a count failed.
    Err() => const <OutboxEntry>[],
  };
});

/// The Profile tab, for all four roles.
///
/// One screen, not four. Everything on it comes from the signed-in [AppUser]
/// and the outbox, and neither of those needs to know which role is looking.
/// The Meter Reader's version and the Cashier's differ only in the words the
/// user object already supplies.
///
/// What is deliberately NOT here: the mockup's fingerprint unlock and theme
/// picker. Neither is built, and a switch that does nothing is worse than an
/// absent one.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(authControllerProvider).value;
    final pending = ref.watch(pendingOutboxProvider);
    final TextTheme text = Theme.of(context).textTheme;

    if (user == null) {
      // Signing out; the router is already moving.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(pendingOutboxProvider),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              _Identity(user: user),
              const SizedBox(height: 24),

              Text('Waiting to sync', style: text.titleSmall),
              const SizedBox(height: 8),
              _SyncCard(pending: pending),

              const SizedBox(height: 24),
              Text('Account', style: text.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: <Widget>[
                      _Row(label: 'Username', value: user.username),
                      const SizedBox(height: 8),
                      _Row(label: 'Role', value: user.roleLabel),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),
              Text('Security', style: text.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text('Change password'),
                  trailing: const Icon(Icons.chevron_right),
                  // `push`, not `go`: this is a task on top of the tab, and
                  // the back arrow has to return to it.
                  onTap: () => context.push(Routes.accountPassword),
                ),
              ),

              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context, ref, pending),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 8),
              Text(
                'Signing out clears the data cached on this device. Anything '
                'still waiting to sync stays saved and is sent when you sign '
                'in again.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// GEN-11. Signing out empties the cache, so somebody holding unsynced work
  /// is told the number before it happens, not after.
  Future<void> _confirmSignOut(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<OutboxEntry>> pending,
  ) async {
    final int waiting = pending.value?.length ?? 0;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          waiting == 0
              ? 'Everything you have recorded has been sent.'
              : 'You still have $waiting item${waiting == 1 ? '' : 's'} '
                  'waiting to sync. They stay saved on this phone and are '
                  'sent when you sign in again.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay signed in'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      // No navigation here on purpose. The router watches the auth state and
      // moves to the login screen by itself, the same way sign-in works.
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

class _Identity extends StatelessWidget {
  final AppUser user;

  const _Identity({required this.user});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Row(
      children: <Widget>[
        Container(
          height: 56,
          width: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colours.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            _initials(user),
            style: text.titleLarge?.copyWith(color: colours.onPrimaryContainer),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(user.fullName, style: text.titleLarge),
              Text('Bohol I Electric Cooperative', style: text.bodySmall),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colours.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(user.roleLabel, style: text.bodySmall),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "Mercedita Gales" becomes "MG". Falls back to one letter rather than
  /// showing nothing when only one name is known.
  static String _initials(AppUser user) {
    final String first = user.firstName.isEmpty ? '' : user.firstName[0];
    final String last = user.lastName.isEmpty ? '' : user.lastName[0];
    final String initials = '$first$last'.toUpperCase();
    return initials.isEmpty ? '?' : initials;
  }
}

class _SyncCard extends StatelessWidget {
  final AsyncValue<List<OutboxEntry>> pending;

  const _SyncCard({required this.pending});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: pending.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          error: (_, _) => Text(
            'Could not read the queue on this phone.',
            style: text.bodyMedium,
          ),
          data: (List<OutboxEntry> entries) {
            if (entries.isEmpty) {
              return Row(
                children: <Widget>[
                  const Icon(Icons.cloud_done_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Everything has been sent.',
                        style: text.bodyMedium),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.cloud_upload_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${entries.length} item'
                        '${entries.length == 1 ? '' : 's'} waiting to sync',
                        style: text.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Each queued action can say what it is - OutboxOperation
                // carries its own description - so the list needs no switch
                // on the operation code.
                for (final OutboxEntry entry in entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('· ${entry.description}', style: text.bodySmall),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;

  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: text.bodyMedium),
        Text(value, style: text.bodyLarge),
      ],
    );
  }
}
