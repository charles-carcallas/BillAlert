import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../data/local/app_database.dart';
import '../data/notifications/android_phone_notifier.dart';
import '../data/notifications/supabase_alert_feed.dart';
import '../data/notifications/workmanager_background_alerts.dart';
import '../data/repositories/auth_repository_impl.dart';
import '../data/repositories/bill_repository_impl.dart';
import '../data/repositories/consumer_repository_impl.dart';
import '../data/repositories/notice_repository_impl.dart';
import '../data/repositories/notification_repository_impl.dart';
import '../data/repositories/outbox_repository_impl.dart';
import '../data/repositories/payment_repository_impl.dart';
import '../data/repositories/reading_repository_impl.dart';
import '../data/security/local_auth_device_unlock.dart';
import '../data/security/secure_fingerprint_setting.dart';
import '../data/sync/supabase_outbox_gateway.dart';
import '../data/sync/sync_service.dart';
import '../domain/notifications/phone_alerts.dart';
import '../domain/outbox/outbox_operation.dart';
import '../domain/repositories/auth_repository.dart';
import '../domain/repositories/bill_repository.dart';
import '../domain/repositories/consumer_repository.dart';
import '../domain/repositories/notice_repository.dart';
import '../domain/repositories/notification_repository.dart';
import '../domain/repositories/outbox_repository.dart';
import '../domain/repositories/payment_repository.dart';
import '../domain/repositories/reading_repository.dart';
import '../domain/security/device_unlock.dart';
import '../domain/security/fingerprint_setting.dart';
import '../domain/time/ph_clock.dart';
import '../domain/usecases/admin/issue_disconnection_notice.dart';
import '../domain/usecases/admin/post_bill_amount.dart';
import '../domain/usecases/auth/change_password.dart';
import '../domain/usecases/auth/sign_in.dart';
import '../domain/usecases/auth/sign_out.dart';
import '../domain/usecases/cashier/record_cash_payment.dart';
import '../domain/usecases/consumer/refresh_phone_alerts.dart';
import '../domain/usecases/reader/load_area_roster.dart';
import '../domain/usecases/reader/record_meter_reading.dart';
import '../domain/value_objects/ids.dart';

/// Where the app is wired together.
///
/// Read the types on the left of every repository provider: they are the
/// abstract classes from `domain/`, not the implementations. That is the
/// dependency inversion in one screenful — the screens and view models above
/// this file can only see the interface, so swapping SupabaseOutboxGateway
/// for a fake in a test, or for a different backend later, changes this file
/// and nothing else.

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

final appDatabaseProvider = Provider<AppDatabase>((Ref ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final supabaseClientProvider = Provider<SupabaseClient>(
  (Ref ref) => Supabase.instance.client,
);

/// SYS-07: the app's idea of "now", always in Philippine time.
final phClockProvider = Provider<PhClock>((Ref ref) => const SystemPhClock());

/// The phone's screen lock — fingerprint, face or PIN. Injected so the rules
/// about when the app locks can be tested without a sensor to press.
final deviceUnlockProvider = Provider<DeviceUnlock>(
  (Ref ref) => LocalAuthDeviceUnlock(),
);

/// Whether fingerprint sign-in is on for this phone, and for whom.
final fingerprintSettingProvider = Provider<FingerprintSetting>(
  (Ref ref) => const SecureFingerprintSetting(),
);

/// Android's notification tray. One instance sits behind both providers
/// below, so the tap handler the household's tabs register is the one used
/// by the notices they show.
final _androidPhoneNotifierProvider = Provider<AndroidPhoneNotifier>(
  (Ref ref) => AndroidPhoneNotifier(),
);

final phoneNotifierProvider = Provider<PhoneNotifier>(
  (Ref ref) => ref.watch(_androidPhoneNotifierProvider),
);

final notificationPermissionProvider = Provider<NotificationPermission>(
  (Ref ref) => ref.watch(_androidPhoneNotifierProvider),
);

/// The household's queued notices and unpaid bills, read straight from
/// Supabase, so the same code runs in the background isolate.
final alertFeedProvider = Provider<AlertFeed>(
  (Ref ref) => SupabaseAlertFeed(ref.watch(supabaseClientProvider)),
);

/// The check Android runs about every fifteen minutes while the app is closed.
final backgroundAlertsProvider = Provider<BackgroundAlerts>(
  (Ref ref) => const WorkmanagerBackgroundAlerts(),
);

/// Shows queued notices and schedules due-date reminders, once, now.
final refreshPhoneAlertsProvider = Provider<RefreshPhoneAlerts>(
  (Ref ref) => RefreshPhoneAlerts(
    feed: ref.watch(alertFeedProvider),
    phone: ref.watch(phoneNotifierProvider),
    clock: ref.watch(phClockProvider),
  ),
);

/// Mints the idempotency key for a queued operation. Injected rather than
/// called directly so a test can hand out predictable ids, and so `domain/`
/// never has to import a uuid package.
final clientUuidFactoryProvider = Provider<ClientUuidFactory>((Ref ref) {
  const uuid = Uuid();
  return () => ClientUuid(uuid.v4());
});

// ---------------------------------------------------------------------------
// Repositories — declared as the abstract type on purpose
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (Ref ref) => AuthRepositoryImpl(
    ref.watch(supabaseClientProvider),
    ref.watch(appDatabaseProvider),
  ),
);

final consumerRepositoryProvider = Provider<ConsumerRepository>(
  (Ref ref) => ConsumerRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final billRepositoryProvider = Provider<BillRepository>(
  (Ref ref) => BillRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (Ref ref) => PaymentRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final noticeRepositoryProvider = Provider<NoticeRepository>(
  (Ref ref) => NoticeRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (Ref ref) => NotificationRepositoryImpl(
    ref.watch(appDatabaseProvider),
    ref.watch(supabaseClientProvider),
  ),
);

final readingRepositoryProvider = Provider<ReadingRepository>(
  (Ref ref) => ReadingRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final outboxRepositoryProvider = Provider<OutboxRepository>(
  (Ref ref) => OutboxRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final outboxGatewayProvider = Provider<OutboxGateway>(
  (Ref ref) => SupabaseOutboxGateway(ref.watch(supabaseClientProvider)),
);

final syncServiceProvider = Provider<SyncService>((Ref ref) {
  final service = SyncService(
    ref.watch(outboxRepositoryProvider),
    ref.watch(outboxGatewayProvider),
  );
  ref.onDispose(service.stop);
  return service;
});

// ---------------------------------------------------------------------------
// Use cases — one per thing a person does
// ---------------------------------------------------------------------------

final signInProvider = Provider<SignIn>(
  (Ref ref) => SignIn(auth: ref.watch(authRepositoryProvider)),
);

final signOutProvider = Provider<SignOut>(
  (Ref ref) => SignOut(auth: ref.watch(authRepositoryProvider)),
);

final changePasswordProvider = Provider<ChangePassword>(
  (Ref ref) => ChangePassword(auth: ref.watch(authRepositoryProvider)),
);

final loadAreaRosterProvider = Provider<LoadAreaRoster>(
  (Ref ref) => LoadAreaRoster(
    consumers: ref.watch(consumerRepositoryProvider),
    readings: ref.watch(readingRepositoryProvider),
    clock: ref.watch(phClockProvider),
  ),
);

final refreshAreaRosterProvider = Provider<RefreshAreaRoster>(
  (Ref ref) =>
      RefreshAreaRoster(consumers: ref.watch(consumerRepositoryProvider)),
);

final recordMeterReadingProvider = Provider<RecordMeterReading>(
  (Ref ref) => RecordMeterReading(
    readings: ref.watch(readingRepositoryProvider),
    outbox: ref.watch(outboxRepositoryProvider),
    clock: ref.watch(phClockProvider),
    newClientUuid: ref.watch(clientUuidFactoryProvider),
  ),
);

final issueDisconnectionNoticeProvider = Provider<IssueDisconnectionNotice>(
  (Ref ref) => IssueDisconnectionNotice(
    outbox: ref.watch(outboxRepositoryProvider),
    clock: ref.watch(phClockProvider),
    newClientUuid: ref.watch(clientUuidFactoryProvider),
  ),
);

/// Closing a served notice. Online only, unlike everything else the Admin
/// does — see [RecordNoticeOutcome] for why it is not queued.
final recordNoticeOutcomeProvider = Provider<RecordNoticeOutcome>(
  (Ref ref) => RecordNoticeOutcome(
    notices: ref.watch(noticeRepositoryProvider),
  ),
);

final postBillAmountProvider = Provider<PostBillAmount>(
  (Ref ref) => PostBillAmount(
    outbox: ref.watch(outboxRepositoryProvider),
    clock: ref.watch(phClockProvider),
    newClientUuid: ref.watch(clientUuidFactoryProvider),
  ),
);

final recordCashPaymentProvider = Provider<RecordCashPayment>(
  (Ref ref) => RecordCashPayment(
    outbox: ref.watch(outboxRepositoryProvider),
    clock: ref.watch(phClockProvider),
    newClientUuid: ref.watch(clientUuidFactoryProvider),
  ),
);
