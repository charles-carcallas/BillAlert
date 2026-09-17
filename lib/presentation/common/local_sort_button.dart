import 'package:flutter/material.dart';

import 'expandable_bottom_sheet.dart';

enum LocalNameSort { az, za }

const List<LocalSortOption<LocalNameSort>> localNameSortOptions =
    <LocalSortOption<LocalNameSort>>[
      LocalSortOption(
        value: LocalNameSort.az,
        label: 'Name A–Z',
        icon: Icons.sort_by_alpha,
      ),
      LocalSortOption(
        value: LocalNameSort.za,
        label: 'Name Z–A',
        icon: Icons.sort_by_alpha,
      ),
    ];

int compareNames(String a, String b, LocalNameSort order) {
  final compared = a.toLowerCase().compareTo(b.toLowerCase());
  return order == LocalNameSort.az ? compared : -compared;
}

/// One local sort choice. Sorting happens against records already loaded on
/// the device, so selecting an option never needs a connection.
final class LocalSortOption<T> {
  final T value;
  final String label;
  final IconData icon;

  const LocalSortOption({
    required this.value,
    required this.label,
    required this.icon,
  });
}

/// Compact Sort control shared by searchable operational lists.
class LocalSortButton<T> extends StatelessWidget {
  final T value;
  final List<LocalSortOption<T>> options;
  final ValueChanged<T> onChanged;
  final Key? buttonKey;

  const LocalSortButton({
    required this.value,
    required this.options,
    required this.onChanged,
    this.buttonKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final selected = options.firstWhere((option) => option.value == value);
    return OutlinedButton.icon(
      key: buttonKey,
      onPressed: () => _choose(context),
      icon: const Icon(Icons.sort, size: 19),
      label: Text(selected.label, overflow: TextOverflow.ellipsis),
      // Filled like the search field it sits beside, so the pair reads as
      // one control row on a tinted panel as well as on the page.
      style: OutlinedButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      ),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final chosen = await showExpandableBottomSheet<T>(
      context: context,
      initialSize: 0.5,
      builder: (sheetContext, scrollController) => ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: <Widget>[
          Text('Sort by', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final option in options)
            ListTile(
              leading: Icon(option.icon),
              title: Text(option.label),
              trailing: option.value == value
                  ? Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
              selected: option.value == value,
              onTap: () => Navigator.of(sheetContext).pop(option.value),
            ),
        ],
      ),
    );
    if (chosen != null && chosen != value) onChanged(chosen);
  }
}
