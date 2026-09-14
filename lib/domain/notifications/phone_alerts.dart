import '../../core/result/result.dart';
import '../entities/bill.dart';
import '../value_objects/ids.dart';

/// A notification the server queued for this household's phone that the phone
/// has not shown yet.
///
/// Only the id and type cross over. The row's `message_content` carries peso
/// amounts, and a phone notification can be read by anyone who picks the
/// phone up, so the words shown are chosen on the phone from the type alone.
final class PendingPhoneAlert {
  final NotificationId id;

  /// bill_ready, pre_due_reminder, overdue or disconnection.
  final String type;

  const PendingPhoneAlert({required this.id, required this.type});
}

/// What the phone needs from the server to keep its household told.
///
/// Read straight from Supabase, never from the encrypted cache. The background
/// check runs in its own isolate while the app may be open in another, and
/// two isolates must not share that database file.
abstract class AlertFeed {
  /// The household the saved session belongs to. Null when nobody is signed
  /// in, or when the person signed in is staff rather than a household.
  Future<Result<ConsumerId?>> signedInHousehold();

  /// Push notifications queued for [household] and not yet shown.
  Future<Result<List<PendingPhoneAlert>>> pendingAlerts(ConsumerId household);

  /// Records that [id] was shown on the phone: status `sent`, with the time.
  Future<Result<void>> markShown(NotificationId id);

  /// Priced bills of [household] that are not fully paid.
  Future<Result<List<Bill>>> unpaidBills(ConsumerId household);

  /// `settings.predue_reminder_days`, or null if the server does not say.
  Future<Result<int?>> reminderDaysBeforeDue();
}

/// Where tapping a notification takes the household.
abstract final class PhoneNoticePayload {
  /// A notice the server queued: open the Inbox, where it is listed.
  static const String inbox = 'inbox';

  /// A due-date reminder: open the Bill tab, where the bill is.
  static const String bill = 'bill';
}

/// One notification for the phone's tray, now or at a scheduled time.
final class PhoneNotice {
  /// Stable for the same alert or bill — see [stableNoticeId].
  final int id;
  final String title;
  final String body;
  final String payload;

  const PhoneNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });
}

/// The phone's notification tray.
abstract class PhoneNotifier {
  /// Prepares the tray. [onTap] receives the payload of a tapped notice.
  Future<void> initialize({void Function(String? payload)? onTap});

  /// The payload of the notice that launched the app, if one did.
  Future<String?> launchPayload();

  /// Whether a shown notice would actually appear. False when the household
  /// has turned BillAlert's notifications off.
  Future<bool> canNotify();

  Future<void> show(PhoneNotice notice);

  /// Shows [notice] at [atUtc], whether or not the app is running then.
  Future<void> schedule(PhoneNotice notice, {required DateTime atUtc});

  /// Ids of notices scheduled and not yet shown.
  Future<Set<int>> scheduledIds();

  Future<void> cancel(int id);

  /// Removes every notice this app has shown or scheduled.
  Future<void> cancelAll();
}

/// Permission to show notifications at all (Android 13 and later ask).
abstract class NotificationPermission {
  Future<bool> isGranted();

  /// Shows the system prompt. Android shows it at most twice per install.
  Future<bool> request();

  /// Opens BillAlert's notification settings, for a household that said no.
  Future<void> openSettings();
}

/// The check that runs while the app is closed.
abstract class BackgroundAlerts {
  /// Starts the periodic check. Safe to call again: it is not duplicated.
  Future<void> start();

  Future<void> stop();
}

/// A notification id that is the same every time for the same [key], in
/// every isolate and every run of the app.
///
/// Android replaces a notification that reuses an id, so a notice shown twice
/// — say, because marking it shown failed on a bad signal — replaces itself
/// instead of stacking a duplicate. `String.hashCode` promises none of that;
/// this is 32-bit FNV-1a, trimmed to the non-negative ints Android accepts.
int stableNoticeId(String key) {
  int hash = 0x811c9dc5;
  for (final int unit in key.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
