import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/consumer.dart' as domain;
import '../../domain/outbox/outbox_entry.dart';
import '../auth/app_lock_controller.dart';
import '../auth/auth_controller.dart';
import '../consumer/consumer_app_bar.dart';
import '../consumer/edit_contact_number_sheet.dart';
import '../providers.dart';
import '../router.dart';
import 'staff_app_bar.dart';

/// Work the app is holding that has not reached the server yet.
///
/// Read here rather than passed in, so the number on the Profile screen is
/// the outbox's own answer and cannot drift from it.
final pendingOutboxProvider = FutureProvider<List<OutboxEntry>>((
  Ref ref,
) async {
  final result = await ref.watch(outboxRepositoryProvider).pending();
  return switch (result) {
    Ok(:final value) => value,
    // A queue that cannot be read is reported as empty rather than as an
    // error: the Profile screen's job is signing out, and it must not become
    // unusable because a count failed.
    Err() => const <OutboxEntry>[],
  };
});

/// The household record supplies details that are not stored on the auth
/// profile, such as the consumer number and SMS contact.
final profileConsumerProvider = FutureProvider<domain.Consumer?>((
  Ref ref,
) async {
  final result = await ref.watch(consumerRepositoryProvider).signedInConsumer();
  return switch (result) {
    Ok(:final value) => value,
    Err() => null,
  };
});

/// Whether this phone can use fingerprint sign-in, and whether it is on for
/// the signed-in person. Read here, so the switch shows the setting's own
/// answer rather than a copy of it that could drift.
final fingerprintStatusProvider = FutureProvider<({bool available, bool on})>((
  Ref ref,
) async {
  final AppUser? user = await ref.watch(authControllerProvider.future);
  final bool available = await ref.watch(deviceUnlockProvider).isAvailable();
  if (user == null || !available) return (available: available, on: false);
  final bool on = await ref.watch(fingerprintSettingProvider).isOnFor(user.id);
  return (available: true, on: on);
});

/// The Profile tab, for all four roles.
///
/// One screen, not four. Everything on it comes from the signed-in [AppUser]
/// and the outbox, and neither of those needs to know which role is looking.
/// The Meter Reader's version and the Cashier's differ only in the words the
/// user object already supplies.
///
/// What is deliberately NOT here: the mockup's theme picker. It is not built,
/// and a switch that does nothing is worse than an absent one.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(authControllerProvider).value;
    final pending = ref.watch(pendingOutboxProvider);
    final AsyncValue<domain.Consumer?>? consumer = user is ConsumerUser
        ? ref.watch(profileConsumerProvider)
        : null;

    if (user == null) {
      // Signing out; the router is already moving.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: user is ConsumerUser
          ? const ConsumerAppBar(title: 'Profile')
          : user is CashierUser
          ? const StaffAppBar(title: 'Profile')
          : AppBar(title: const Text('Profile')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(pendingOutboxProvider);
            ref.invalidate(fingerprintStatusProvider);
            if (user is ConsumerUser) ref.invalidate(profileConsumerProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _Identity(user: user, consumer: consumer?.value),
              if (user is ConsumerUser) ...<Widget>[
                const SizedBox(height: 18),
                const _SectionHeader(
                  icon: Icons.notifications_none,
                  label: 'Notifications',
                ),
                const SizedBox(height: 6),
                const _Panel(
                  children: <Widget>[
                    _SettingRow(
                      title: 'Inbox alerts',
                      subtitle:
                          'Bill ready, payment reminders, overdue alerts, and notices',
                      trailing: Icon(Icons.check_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const _SectionHeader(
                  icon: Icons.sms_outlined,
                  label: 'SMS delivery',
                ),
                const SizedBox(height: 6),
                _SmsPanel(
                  consumer: consumer,
                  onEdit: consumer?.hasValue == true
                      ? () async {
                          final String? saved =
                              await showEditConsumerContactNumber(
                                context,
                                currentNumber: consumer?.value?.contactNumber,
                              );
                          if (saved != null) {
                            ref.invalidate(profileConsumerProvider);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'SMS number updated to $saved.',
                                  ),
                                ),
                              );
                            }
                          }
                        }
                      : null,
                ),
              ],
              const SizedBox(height: 18),
              const _SectionHeader(icon: Icons.sync, label: 'Sync'),
              const SizedBox(height: 6),
              _SyncPanel(pending: pending),
              const SizedBox(height: 18),
              const _SectionHeader(
                icon: Icons.manage_accounts_outlined,
                label: 'Account',
              ),
              const SizedBox(height: 6),
              _Panel(
                children: <Widget>[
                  _DetailRow(label: 'Username', value: user.username),
                  const Divider(),
                  _DetailRow(label: 'Role', value: user.roleLabel),
                ],
              ),
              const SizedBox(height: 18),
              const _SectionHeader(icon: Icons.lock_outline, label: 'Security'),
              const SizedBox(height: 6),
              _Panel(
                children: <Widget>[
                  _SettingRow(
                    title: 'Change password',
                    subtitle: 'Update the password used to sign in',
                    trailing: const Icon(Icons.chevron_right),
                    // `push`, not `go`: this is a task on top of the tab, and
                    // the back arrow has to return to it.
                    onTap: () => context.push(Routes.accountPassword),
                  ),
                  const Divider(),
                  _FingerprintRow(user: user),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context, ref, pending),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(color: Theme.of(context).colorScheme.error),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Signing out clears the data cached on this device. Anything '
                'still waiting to sync stays saved and is sent when you sign '
                'in again.',
                style: Theme.of(context).textTheme.bodySmall,
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

class _SmsPanel extends StatelessWidget {
  final AsyncValue<domain.Consumer?>? consumer;
  final VoidCallback? onEdit;

  const _SmsPanel({required this.consumer, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colours = Theme.of(context).colorScheme;
    final String number =
        consumer?.when(
          data: (value) => value?.contactNumber ?? 'No mobile number on file',
          loading: () => 'Loading contact number…',
          error: (_, _) => 'Contact number unavailable',
        ) ??
        'Contact number unavailable';

    return _Panel(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colours.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.sms_outlined, color: colours.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Alerts are also sent to this number. Keep it current '
                      'so important notices still arrive.',
                      style: text.bodySmall,
                    ),
                    const SizedBox(height: 9),
                    SelectableText(
                      number,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(
                        consumer?.value?.contactNumber == null
                            ? 'Add SMS number'
                            : 'Edit SMS number',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Identity extends StatelessWidget {
  final AppUser user;
  final domain.Consumer? consumer;

  const _Identity({required this.user, this.consumer});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: 56,
            width: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colours.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Text(
              _initials(user),
              style: text.titleLarge?.copyWith(
                color: colours.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(user.fullName, style: text.titleLarge),
                Text(
                  user is ConsumerUser
                      ? consumer?.consumerNo.value ?? user.username
                      : 'Bohol I Electric Cooperative',
                  style: text.bodySmall?.copyWith(letterSpacing: 0.3),
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colours.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    user.roleLabel.toUpperCase(),
                    style: text.labelSmall?.copyWith(
                      color: colours.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 15, color: colours.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colours.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final List<Widget> children;

  const _Panel({required this.children});

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colours.surfaceContainerLowest,
        border: Border.all(color: colours.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }
}

class _SyncPanel extends StatelessWidget {
  final AsyncValue<List<OutboxEntry>> pending;

  const _SyncPanel({required this.pending});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return _Panel(
      children: <Widget>[
        Padding(
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
                      child: Text(
                        'Everything has been sent.',
                        style: text.bodyMedium,
                      ),
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
                      child: Text(
                        '· ${entry.description}',
                        style: text.bodySmall,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: text.bodyMedium),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconTheme(
              data: IconThemeData(
                color: onTap == null
                    ? colours.primary
                    : colours.onSurfaceVariant,
                size: 20,
              ),
              child: trailing,
            ),
          ],
        ),
      ),
    );
  }
}

/// Fingerprint sign-in, on or off, for the signed-in person on this phone.
///
/// Both directions ask the phone to confirm first, through the same
/// controller the offer after sign-in uses. Turning it off removes the lock,
/// so it must not be something whoever picks up an open phone can do quietly.
///
/// On a phone with no screen lock, the switch is shown off and disabled with
/// the reason beside it, rather than hidden or left tappable with nothing
/// behind it.
class _FingerprintRow extends ConsumerWidget {
  final AppUser user;

  const _FingerprintRow({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(fingerprintStatusProvider);
    final bool available = status.value?.available ?? false;
    final bool on = status.value?.on ?? false;

    final String subtitle = status.isLoading
        ? 'Checking this phone…'
        : available
        ? "Unlock BillAlert with your fingerprint or your phone's PIN instead "
              'of your password'
        : 'This phone has no screen lock to unlock BillAlert with';

    return _SettingRow(
      title: 'Fingerprint sign-in',
      subtitle: subtitle,
      trailing: Switch(
        value: on,
        onChanged: status.isLoading || !available
            ? null
            : (bool turnOn) => _change(context, ref, turnOn),
      ),
    );
  }

  Future<void> _change(BuildContext context, WidgetRef ref, bool turnOn) async {
    final AppLockController lock = ref.read(appLockControllerProvider.notifier);
    final AppFailure? failure = turnOn
        ? await lock.turnOnFor(user)
        : await lock.turnOff();
    ref.invalidate(fingerprintStatusProvider);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failure?.message ??
              (turnOn
                  ? 'Fingerprint sign-in is on for this phone.'
                  : 'Fingerprint sign-in is off for this phone.'),
        ),
      ),
    );
  }
}
