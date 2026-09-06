import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

/// A stand-in home screen for a role nobody has built yet.
///
/// Composed into the three placeholder screens rather than extended by them.
/// A `BaseScreen` that every screen inherits from would share the same code
/// and be much harder to defend: this is a widget the others use, not a
/// parent class they are forced into.
class RolePlaceholder extends ConsumerWidget {
  final String title;
  final String owner;
  final List<String> firstScreens;

  const RolePlaceholder({
    required this.title,
    required this.owner,
    required this.firstScreens,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            if (user != null) ...<Widget>[
              Text(
                user.fullName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(user.roleLabel),
              const SizedBox(height: 24),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'This section is not built yet.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text('Owned by $owner.'),
                    const SizedBox(height: 16),
                    const Text('First screens to build:'),
                    const SizedBox(height: 8),
                    for (final String screen in firstScreens)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('  - $screen'),
                      ),
                    const SizedBox(height: 16),
                    const Text(
                      'The use cases and abstract repositories for this role '
                      'already exist under domain/. Write the repository '
                      'implementation and the screen; do not call Supabase '
                      'from a widget.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
