import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/notification_repository.dart';
import '../../domain/usecases/consumer/load_notification_details.dart';
import '../providers.dart';

/// Kept beside the sheet that uses it, like the admin use cases, so the
/// shared provider composition stays unchanged.
final loadNotificationDetailsProvider = Provider<LoadNotificationDetails>(
  (Ref ref) => LoadNotificationDetails(
    bills: ref.watch(billRepositoryProvider),
    notices: ref.watch(noticeRepositoryProvider),
  ),
);

/// The details of the notification a household opened.
///
/// autoDispose, so opening it again asks again: a notice settled since, or a
/// bill that could not be read without signal, is not remembered.
final notificationDetailsProvider = FutureProvider.autoDispose
    .family<NotificationDetails, AppNotification>(
      (Ref ref, AppNotification notification) =>
          ref.watch(loadNotificationDetailsProvider)(notification),
    );
