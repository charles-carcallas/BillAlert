import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/entities/consumer.dart' as domain;
import '../../domain/notifications/phone_alerts.dart';
import '../../domain/outbox/outbox_entry.dart';
import '../auth/app_lock_controller.dart';
import '../auth/auth_controller.dart';
import '../consumer/consumer_app_bar.dart';
import '../consumer/edit_contact_number_sheet.dart';
import '../providers.dart';
import '../router.dart';
import 'appearance_setting.dart';
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

/// Whether urgent due-date alerts are on for this phone, and whether they fill
/// the screen here or pop up. Read here, so the switch shows the setting's own
/// answer.
final urgentAlertsStatusProvider =
    FutureProvider<({bool on, bool fillsScreen})>((Ref ref) async {
      final bool on = await ref.watch(urgentAlertsSettingProvider).isOn();
      final bool fillsScreen = await ref
          .watch(fullScreenAlertsProvider)
          .fillsScreen();
      return (on: on, fillsScreen: fillsScreen);
    });

/// The Profile tab, for all four roles.
///
/// One screen, not four. Everything on it comes from the signed-in [AppUser]
/// and the outbox, and neither of those needs to know which role is looking.
/// The Meter Reader's version and the Cashier's differ only in the words the
/// user object already supplies.
///
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

    final ColorScheme colours = Theme.of(context).colorScheme;

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
            if (user is ConsumerUser) {
              ref.invalidate(profileConsumerProvider);
              ref.invalidate(urgentAlertsStatusProvider);
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: <Widget>[
              _ProfileHeader(user: user, consumer: consumer?.value),
              if (user is ConsumerUser)
                _Group(
                  title: 'Notifications',
                  footer:
                      'Alerts are also sent to your SMS number. Keep it '
                      'current so important notices still arrive.',
                  children: <Widget>[
                    const _SettingRow(
                      icon: Icons.notifications_none,
                      title: 'Inbox alerts',
                      subtitle:
                          'Bill ready, payment reminders, overdue alerts, and notices',
                      trailing: Icon(Icons.check_circle_outline),
                    ),
                    const _UrgentAlertsRow(),
                    _SmsRow(
                      consumer: consumer,
                      onEdit: consumer?.hasValue == true
                          ? () async {
                              final String? saved =
                                  await showEditConsumerContactNumber(
                                    context,
                                    currentNumber:
                                        consumer?.value?.contactNumber,
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
                ),
              const _Group(
                title: 'Appearance',
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _RowText(
                          icon: Icons.palette_outlined,
                          title: 'Theme',
                          subtitle: 'Choose how BillAlert looks on this device',
                        ),
                        SizedBox(height: 14),
                        AppearanceSetting(),
                      ],
                    ),
                  ),
                ],
              ),
              _Group(
                title: 'Security',
                children: <Widget>[
                  _SettingRow(
                    icon: Icons.lock_outline,
                    title: 'Change password',
                    subtitle: 'Update the password used to sign in',
                    trailing: const Icon(Icons.chevron_right),
                    // `push`, not `go`: this is a task on top of the tab, and
                    // the back arrow has to return to it.
                    onTap: () => context.push(Routes.accountPassword),
                  ),
                  _FingerprintRow(user: user),
                ],
              ),
              _Group(
                title: 'This phone',
                footer:
                    'Signing out clears the data cached on this device. '
                    'Anything still waiting to sync stays saved and is sent '
                    'when you sign in again.',
                children: <Widget>[
                  _SyncRow(pending: pending),
                  _SettingRow(
                    icon: Icons.logout,
                    tint: colours.error,
                    title: 'Sign out',
                    subtitle: 'Leave BillAlert on this phone',
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _confirmSignOut(context, ref, pending),
                  ),
                ],
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

/// The household's SMS delivery number, with the way to change it.
class _SmsRow extends StatelessWidget {
  final AsyncValue<domain.Consumer?>? consumer;
  final VoidCallback? onEdit;

  const _SmsRow({required this.consumer, this.onEdit});

  @override
  Widget build(BuildContext context) {
    final String number =
        consumer?.when(
          data: (value) => value?.contactNumber ?? 'No mobile number on file',
          loading: () => 'Loading contact number…',
          error: (_, _) => 'Contact number unavailable',
        ) ??
        'Contact number unavailable';

    return _SettingRow(
      icon: Icons.sms_outlined,
      title: 'SMS delivery number',
      subtitle: number,
      trailing: TextButton(
        onPressed: onEdit,
        child: Text(consumer?.value?.contactNumber == null ? 'Add' : 'Edit'),
      ),
    );
  }
}

/// Who is signed in, with the account facts folded in rather than repeated
/// in a card of their own further down.
class _ProfileHeader extends StatelessWidget {
  final AppUser user;
  final domain.Consumer? consumer;

  const _ProfileHeader({required this.user, this.consumer});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
      decoration: BoxDecoration(
        color: colours.primary.withValues(alpha: 0.08),
        border: Border.all(color: colours.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                height: 60,
                width: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colours.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(user),
                  style: text.titleLarge?.copyWith(
                    color: colours.onPrimary,
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
                    const SizedBox(height: 2),
                    Text(
                      user is ConsumerUser
                          ? consumer?.consumerNo.value ?? user.username
                          : 'Bohol I Electric Cooperative',
                      style: text.bodySmall?.copyWith(
                        color: colours.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: colours.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: _Fact(label: 'Username', value: user.username),
                  ),
                  VerticalDivider(
                    width: 1,
                    indent: 4,
                    endIndent: 4,
                    color: colours.outlineVariant,
                  ),
                  Expanded(
                    child: _Fact(label: 'Role', value: user.roleLabel),
                  ),
                ],
              ),
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

class _Fact extends StatelessWidget {
  final String label;
  final String value;

  const _Fact({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: <Widget>[
          Text(
            label,
            style: text.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall,
          ),
        ],
      ),
    );
  }
}

/// A titled card of rows. The title sits close to its own card and far from
/// the one above, so each group reads as one unit, and the rows inside are
/// split by dividers that start where the text does.
class _Group extends StatelessWidget {
  final String title;
  final String? footer;
  final List<Widget> children;

  const _Group({required this.title, required this.children, this.footer});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: text.titleSmall?.copyWith(
                color: colours.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: colours.surfaceContainerLowest,
              border: Border.all(color: colours.outlineVariant),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 68,
                      color: colours.outlineVariant.withValues(alpha: 0.6),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                footer!,
                style: text.bodySmall?.copyWith(
                  color: colours.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// What has not reached the server yet, as a row like every other.
class _SyncRow extends StatelessWidget {
  final AsyncValue<List<OutboxEntry>> pending;

  const _SyncRow({required this.pending});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return pending.when(
      loading: () => const _SettingRow(
        icon: Icons.sync,
        title: 'Sync',
        subtitle: 'Checking this phone…',
        trailing: SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, _) => const _SettingRow(
        icon: Icons.sync_problem_outlined,
        title: 'Sync',
        subtitle: 'Could not read the queue on this phone.',
        trailing: SizedBox.shrink(),
      ),
      data: (List<OutboxEntry> entries) {
        if (entries.isEmpty) {
          return const _SettingRow(
            icon: Icons.cloud_done_outlined,
            title: 'Sync',
            subtitle: 'Everything has been sent.',
            trailing: Icon(Icons.check_circle_outline),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _RowText(
                icon: Icons.cloud_upload_outlined,
                title: 'Sync',
                subtitle:
                    '${entries.length} item'
                    '${entries.length == 1 ? '' : 's'} waiting to sync',
              ),
              const SizedBox(height: 6),
              // Each queued action can say what it is - OutboxOperation
              // carries its own description - so the list needs no switch
              // on the operation code.
              for (final OutboxEntry entry in entries)
                Padding(
                  padding: const EdgeInsets.only(left: 52, top: 2),
                  child: Text('· ${entry.description}', style: text.bodySmall),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The icon tile, title and subtitle every row on the screen starts with, so
/// the cards share one rhythm.
class _RowText extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color? tint;

  const _RowText({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;
    final Color colour = tint ?? colours.primary;

    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 21, color: colour),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: text.titleSmall?.copyWith(color: tint)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: text.bodySmall?.copyWith(
                  color: colours.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;
  final Color? tint;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _RowText(
                icon: icon,
                title: title,
                subtitle: subtitle,
                tint: tint,
              ),
            ),
            const SizedBox(width: 8),
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
      icon: Icons.fingerprint,
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

/// Urgent due-date alerts, on or off, for this phone.
///
/// On Android 14 and later the reminder fills the screen, which Android makes
/// the household allow once, so turning the switch on opens that page when it
/// is needed. Older phones get a loud pop-up, which needs nothing allowed.
class _UrgentAlertsRow extends ConsumerWidget {
  const _UrgentAlertsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(urgentAlertsStatusProvider);
    final bool on = status.value?.on ?? true;
    final bool fillsScreen = status.value?.fillsScreen ?? false;

    final String subtitle = status.isLoading
        ? 'Checking this phone…'
        : fillsScreen
        ? 'Before a bill is due, the reminder fills the screen'
        : 'Before a bill is due, the reminder pops up with a loud sound';

    return _SettingRow(
      icon: Icons.alarm,
      title: 'Urgent due-date alerts',
      subtitle: subtitle,
      trailing: Switch(
        value: on,
        onChanged: status.isLoading
            ? null
            : (bool turnOn) => _change(context, ref, turnOn, fillsScreen),
      ),
    );
  }

  Future<void> _change(
    BuildContext context,
    WidgetRef ref,
    bool turnOn,
    bool fillsScreen,
  ) async {
    final UrgentAlertsSetting setting = ref.read(urgentAlertsSettingProvider);
    String message;
    try {
      if (turnOn) {
        await setting.turnOn();
        final bool allowed =
            !fillsScreen || await ref.read(fullScreenAlertsProvider).allow();
        message = allowed
            ? 'Urgent due-date alerts are on.'
            : 'Urgent due-date alerts are on. Allow full-screen alerts for '
                  'BillAlert in Android settings, or the reminder pops up '
                  'instead.';
      } else {
        await setting.turnOff();
        message =
            'Urgent due-date alerts are off. Reminders arrive as ordinary '
            'notifications.';
      }
    } catch (_) {
      message = 'That setting could not be saved on this phone. Try again.';
    }
    ref.invalidate(urgentAlertsStatusProvider);

    // Reminders already waiting keep the style they were scheduled with until
    // they are scheduled again, so do that now rather than at the next check.
    try {
      await ref.read(refreshPhoneAlertsProvider)();
    } catch (_) {}

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
