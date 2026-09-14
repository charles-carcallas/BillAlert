import 'package:billalert/core/errors/app_failure.dart';
import 'package:billalert/core/result/result.dart';
import 'package:billalert/domain/entities/bill.dart';
import 'package:billalert/domain/notifications/phone_alerts.dart';
import 'package:billalert/domain/time/ph_clock.dart';
import 'package:billalert/domain/value_objects/ids.dart';
import 'package:billalert/domain/value_objects/ph_date.dart';

/// The server's side of phone notifications, held in memory.
final class FakeAlertFeed implements AlertFeed {
  Result<ConsumerId?> household = const Ok<ConsumerId?>(
    ConsumerId('consumer-1'),
  );
  List<PendingPhoneAlert> pending = <PendingPhoneAlert>[];
  List<Bill> unpaid = <Bill>[];
  AppFailure? unpaidFailure;
  int? reminderDays = 3;
  final List<NotificationId> markedShown = <NotificationId>[];

  @override
  Future<Result<ConsumerId?>> signedInHousehold() async => household;

  @override
  Future<Result<List<PendingPhoneAlert>>> pendingAlerts(
    ConsumerId household,
  ) async => Ok<List<PendingPhoneAlert>>(pending);

  @override
  Future<Result<void>> markShown(NotificationId id) async {
    markedShown.add(id);
    return const Ok<void>(null);
  }

  @override
  Future<Result<List<Bill>>> unpaidBills(ConsumerId household) async {
    final AppFailure? failure = unpaidFailure;
    return failure == null ? Ok<List<Bill>>(unpaid) : Err<List<Bill>>(failure);
  }

  @override
  Future<Result<int?>> reminderDaysBeforeDue() async => Ok<int?>(reminderDays);
}

/// A notice scheduled for later.
final class ScheduledNotice {
  final PhoneNotice notice;
  final DateTime atUtc;

  const ScheduledNotice(this.notice, this.atUtc);
}

/// The phone's notification tray, held in memory.
final class FakePhoneNotifier implements PhoneNotifier {
  bool allowed = true;
  final List<PhoneNotice> shown = <PhoneNotice>[];
  final Map<int, ScheduledNotice> scheduled = <int, ScheduledNotice>{};
  int cancelAllCalls = 0;

  @override
  Future<void> initialize({void Function(String? payload)? onTap}) async {}

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<bool> canNotify() async => allowed;

  @override
  Future<void> show(PhoneNotice notice) async {
    shown.add(notice);
  }

  @override
  Future<void> schedule(PhoneNotice notice, {required DateTime atUtc}) async {
    scheduled[notice.id] = ScheduledNotice(notice, atUtc);
  }

  @override
  Future<Set<int>> scheduledIds() async => scheduled.keys.toSet();

  @override
  Future<void> cancel(int id) async {
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    shown.clear();
    scheduled.clear();
  }
}

/// A clock stopped at one instant.
final class StoppedClock implements PhClock {
  final DateTime now;

  const StoppedClock(this.now);

  @override
  DateTime nowUtc() => now;

  @override
  PhDate today() => PhDate.at(now);
}

/// The background check, counting starts and stops instead of reaching
/// Android's WorkManager.
final class FakeBackgroundAlerts implements BackgroundAlerts {
  int starts = 0;
  int stops = 0;

  @override
  Future<void> start() async {
    starts++;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}
