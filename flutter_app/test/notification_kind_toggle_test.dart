import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/notifications_provider.dart';

void main() {
  test('notificationKindPrefKey maps server kinds to prefs', () {
    final reorder = NotificationItem(
      id: 'srv_1',
      type: NotificationType.serverInApp,
      title: 'Reorder',
      subtitle: 'body',
      createdAt: DateTime.now(),
      serverKind: 'reorder_request',
    );
    expect(notificationKindPrefKey(reorder), 'staff_alert');

    expect(
      notificationKindPrefKey(
        NotificationItem(
          id: 'srv_2',
          type: NotificationType.serverInApp,
          title: 'Idle',
          subtitle: '',
          createdAt: DateTime.now(),
          serverKind: 'delivery_idle',
        ),
      ),
      'delivery',
    );

    expect(
      notificationKindPrefKey(
        NotificationItem(
          id: 'srv_3',
          type: NotificationType.serverInApp,
          title: 'Evening',
          subtitle: '',
          createdAt: DateTime.now(),
          serverKind: 'physical_count_reminder',
        ),
      ),
      'physical_reminder',
    );
  });

  test('notificationPassesKindToggles respects enabled set', () {
    final n = NotificationItem(
      id: 'srv_2',
      type: NotificationType.serverInApp,
      title: 'Low',
      subtitle: 'body',
      createdAt: DateTime.now(),
      serverKind: 'low_stock',
    );
    expect(notificationPassesKindToggles(n, {'low_stock'}), isTrue);
    expect(notificationPassesKindToggles(n, {'delivery'}), isFalse);
    expect(notificationPassesKindToggles(n, {}), isFalse);
  });
}
