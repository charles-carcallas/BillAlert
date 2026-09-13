import 'package:flutter/material.dart';

/// A consistent search box for filtering records already loaded on-device.
///
/// It deliberately has no submit callback: these searches never issue a
/// network request, which keeps the Reader's screens useful without signal.
class LocalSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final Key? fieldKey;

  const LocalSearchField({
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.fieldKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    textInputAction: TextInputAction.search,
    onChanged: onChanged,
    decoration: InputDecoration(
      hintText: hintText,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                controller.clear();
                onChanged('');
              },
              icon: const Icon(Icons.close),
            ),
    ),
  );
}
