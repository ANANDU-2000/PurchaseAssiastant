import '../../../core/api/hexa_api.dart';
import '../../../core/providers/notifications_provider.dart';

/// Server-backed notification CRUD + client events.
class NotificationsRepository {
  const NotificationsRepository(this._api);

  final HexaApi _api;

  Future<List<NotificationItem>> fetchFeed({
    required String businessId,
    String? category,
    String? priority,
    bool unreadOnly = false,
    String? q,
  }) async {
    final rows = await _api.listAppNotifications(
      businessId: businessId,
      perPage: 50,
      fetchAllPages: true,
    );
    return rows.map(notificationItemFromServerRow).toList();
  }

  Future<Map<String, dynamic>> summary(String businessId) =>
      _api.appNotificationsSummary(businessId: businessId);

  Future<void> markRead({
    required String businessId,
    required String notificationId,
  }) async {
    await _api.patchAppNotificationRead(
      businessId: businessId,
      notificationId: notificationId,
    );
  }

  Future<int> markAllRead({required String businessId, String? kind}) =>
      _api.markAllAppNotificationsRead(businessId: businessId, kind: kind);

  Future<void> reportExportFailed({
    required String businessId,
    required String purchaseId,
    required String humanId,
    required String operation,
  }) async {
    await _api.postClientNotificationEvent(
      businessId: businessId,
      kind: 'export_failed',
      title: 'PDF export failed',
      body: 'Could not $operation purchase $humanId. Please try again.',
      priority: 'critical',
      category: 'system',
      actionRoute: '/purchase/detail/$purchaseId',
      dedupeKey: 'export_failed:$purchaseId:$operation',
      relatedPurchaseId: purchaseId,
    );
  }
}
