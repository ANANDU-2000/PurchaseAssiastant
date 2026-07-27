import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;

/// Single fetch for list + unread + summary (one inflight per business).
class AppNotificationsBundle {
  const AppNotificationsBundle({
    required this.rows,
    required this.unreadCount,
    required this.summary,
  });

  final List<Map<String, dynamic>> rows;
  final int unreadCount;
  final Map<String, dynamic> summary;
}

final Map<String, Future<AppNotificationsBundle>> _appNotificationsBundleInflight =
    {};

Future<AppNotificationsBundle> _fetchNotificationsBundle(
  Ref ref,
  String businessId,
) {
  return _appNotificationsBundleInflight.putIfAbsent(
    businessId,
    () async {
      final api = ref.read(hexaApiProvider);
      try {
        final results = await Future.wait<Object>([
          api.listAppNotifications(businessId: businessId),
          api.appNotificationUnreadCount(businessId: businessId),
          api.appNotificationsSummary(businessId: businessId),
        ]);
        return AppNotificationsBundle(
          rows: List<Map<String, dynamic>>.from(results[0] as List),
          unreadCount: (results[1] as num?)?.toInt() ?? 0,
          summary: Map<String, dynamic>.from(results[2] as Map),
        );
      } finally {
        _appNotificationsBundleInflight.remove(businessId);
      }
    },
  );
}

final appNotificationsBundleProvider =
    FutureProvider.autoDispose<AppNotificationsBundle>((ref) async {
  final keepAlive = ref.keepAlive();
  final timer = Timer(const Duration(seconds: 120), keepAlive.close);
  ref.onDispose(timer.cancel);
  if (providerSkipApi(ref)) {
    return const AppNotificationsBundle(
      rows: [],
      unreadCount: 0,
      summary: {},
    );
  }
  final session = ref.watch(activeSessionProvider);
  if (session == null) {
    return const AppNotificationsBundle(
      rows: [],
      unreadCount: 0,
      summary: {},
    );
  }
  return _fetchNotificationsBundle(ref, session.primaryBusiness.id);
});

/// Server-backed in-app notifications (GET …/notifications).
final appNotificationsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final bundle = await ref.watch(appNotificationsBundleProvider.future);
  return bundle.rows;
});

final appNotificationUnreadCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final bundle = await ref.watch(appNotificationsBundleProvider.future);
  return bundle.unreadCount;
});

final appNotificationsSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final bundle = await ref.watch(appNotificationsBundleProvider.future);
  return bundle.summary;
});
