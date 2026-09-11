import 'package:flutter/material.dart';
// `Consumer` here means a household, not Riverpod's widget.
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Consumer;
import 'package:go_router/go_router.dart';

import '../../core/errors/app_failure.dart';
import '../../core/result/result.dart';
import '../../domain/entities/consumer.dart';
import '../auth/auth_controller.dart';
import '../common/failure_banner.dart';
import '../common/staff_app_bar.dart';
import '../providers.dart';
import '../router.dart';

/// The households of this Admin's own service area, read from the cache.
///
/// The Admin is at a desk with signal, but reading the cache means this tab
/// behaves the same way the reader's roster does and needs no second code
/// path. Pull to refresh is the only thing here that goes online.
final adminHouseholdsProvider = FutureProvider<List<Consumer>>((Ref ref) async {
  final user = await ref.watch(authControllerProvider.future);
  final areaId = user?.areaId;
  if (areaId == null) {
    throw const PermissionFailure(
      'This screen is for an Area President, and no service area is attached '
      'to the account you are signed in with.',
    );
  }

  final result = await ref.watch(consumerRepositoryProvider).areaRoster(areaId);
  return switch (result) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };
});

/// ADM-03 — Admin › Accounts.
///
/// Every household on the books in this area, and the way to add another.
/// A list rather than a menu of two buttons: before serving a notice or
/// chasing a bill the Area President wants to see the record exists, and
/// after creating one they want to see it appear.
///
/// STAFF accounts (Figma 70:1436) are NOT created here, and the screen says
/// so rather than offering a button that fails. Creating a sign-in account
/// means creating an auth user, which needs the service-role key — a
/// credential that must never be shipped inside a client app, where anyone
/// with the APK can read it out. That is an architectural limit, not an
/// unfinished screen.
class AdminAccountsScreen extends ConsumerWidget {
  const AdminAccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final households = ref.watch(adminHouseholdsProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: const StaffAppBar(title: 'Accounts'),
      floatingActionButton: FloatingActionButton.extended(
        // `push`, so the back arrow returns here. The refresh afterwards goes
        // to the server on purpose: creating a household writes to Supabase
        // and not to this device's cache, so without it the Admin would come
        // back to a list that does not contain what they just created.
        onPressed: () async {
          await context.push(Routes.newConsumer);
          await _refreshFromServer(ref);
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('New consumer'),
      ),
      body: SafeArea(
        child: households.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace _) => Padding(
            padding: const EdgeInsets.all(16),
            child: FailureBanner(
              failure: error is AppFailure
                  ? error
                  : ServerFailure(ServerFailure.defaultMessage, '$error'),
              onRetry: () => ref.invalidate(adminHouseholdsProvider),
            ),
          ),
          data: (List<Consumer> list) => RefreshIndicator(
            onRefresh: () => _refreshFromServer(ref),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: <Widget>[
                if (list.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      children: <Widget>[
                        Icon(
                          Icons.home_outlined,
                          size: 40,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No households on this device yet.',
                          style: text.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Pull down to fetch this area from the server.',
                          style: text.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else ...<Widget>[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.groups_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${list.length} household${list.length == 1 ? '' : 's'} '
                            'in this service area',
                            style: text.titleSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: <Widget>[
                        for (
                          var index = 0;
                          index < list.length;
                          index++
                        ) ...<Widget>[
                          _HouseholdTile(household: list[index]),
                          if (index < list.length - 1)
                            const Divider(indent: 16, endIndent: 16),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Staff accounts', style: text.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          'A meter reader or cashier sign-in cannot be created '
                          'from this app. Doing so needs a service-role key, '
                          'and that key must never be inside an app anyone can '
                          'install. Ask the cooperative to provision the '
                          'account, then it signs in here like any other.',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Refreshes the cached roster from the server, then rebuilds the list.
  ///
  /// A failed refresh keeps whatever is already cached: an out-of-date list
  /// is worth more than an empty one.
  static Future<void> _refreshFromServer(WidgetRef ref) async {
    final user = await ref.read(authControllerProvider.future);
    final areaId = user?.areaId;
    if (areaId != null) {
      await ref.read(consumerRepositoryProvider).refreshAreaRoster(areaId);
    }
    ref.invalidate(adminHouseholdsProvider);
  }
}

class _HouseholdTile extends StatelessWidget {
  final Consumer household;

  const _HouseholdTile({required this.household});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    final colours = Theme.of(context).colorScheme;
    final String initials = <String>[
      if (household.firstName.isNotEmpty) household.firstName[0],
      if (household.lastName.isNotEmpty) household.lastName[0],
    ].join().toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 18,
            backgroundColor: colours.primary.withValues(alpha: 0.11),
            foregroundColor: colours.primary,
            child: Text(initials.isEmpty ? '?' : initials),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(household.fullName, style: text.titleMedium),
                Text(
                  <String>[
                    household.consumerNo.value,
                    if (household.purok != null) household.purok!,
                    if (!household.isActive) 'inactive',
                  ].join(' · '),
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          if (!household.isActive)
            Icon(Icons.block, size: 18, color: colours.error),
        ],
      ),
    );
  }
}
