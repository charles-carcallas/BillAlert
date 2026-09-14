import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/value_objects/ids.dart';

/// What the Inbox was opened to show, when a tapped notification opened it.
final class InboxFocus {
  /// The notice to point at.
  final NotificationId? highlight;

  /// Why a tapped notification landed here instead of on its bill.
  final String? explanation;

  const InboxFocus({this.highlight, this.explanation});
}

/// Set by the notification tap handler just before it opens the Inbox; read
/// by the Inbox; cleared when the Inbox is left or the message dismissed.
class InboxFocusController extends Notifier<InboxFocus> {
  @override
  InboxFocus build() => const InboxFocus();

  void focus({NotificationId? highlight, String? explanation}) =>
      state = InboxFocus(highlight: highlight, explanation: explanation);

  void clear() {
    // The Inbox clears this a moment after it is disposed. If the whole
    // provider container went with it — a hot restart, or the end of a test —
    // there is no focus left to clear, and setting state would throw.
    if (!ref.mounted) return;
    state = const InboxFocus();
  }
}

final inboxFocusProvider = NotifierProvider<InboxFocusController, InboxFocus>(
  InboxFocusController.new,
);
