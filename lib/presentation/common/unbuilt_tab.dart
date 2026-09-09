import 'package:flutter/material.dart';

/// A tab that exists in the navigation but has not been built yet.
///
/// It says so, plainly, and shows nothing else. The alternative - a screen
/// filled with invented figures so it looks finished - is worse than an empty
/// one: a peso amount on a screen is indistinguishable from a real one, and
/// somebody eventually acts on it. Nothing here is mistakable for data.
///
/// Each instance names the Figma frame it will be built from, so the next
/// person does not have to go looking for it.
class UnbuiltTab extends StatelessWidget {
  /// What the app bar says - the same words as the tab.
  final String title;

  /// One sentence on what this screen will show once it is built.
  final String willShow;

  /// The Figma node id, e.g. "20:1141".
  final String figmaNode;

  const UnbuiltTab({
    required this.title,
    required this.willShow,
    required this.figmaNode,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final ColorScheme colours = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.construction_outlined,
                  size: 40,
                  color: colours.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'Not built yet',
                  style: text.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  willShow,
                  style: text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Figma $figmaNode',
                  style: text.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
