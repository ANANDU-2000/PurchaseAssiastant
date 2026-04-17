import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';

enum NotificationType { priceAlert, profitLow, reminder, system, whatsapp }

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    this.isRead = false,
    this.actionRoute,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final bool isRead;
  final String? actionRoute;
}

class NotificationsNotifier extends StateNotifier<List<NotificationItem>> {
  NotificationsNotifier() : super(_seed);

  static final _seed = <NotificationItem>[
    NotificationItem(
      id: 'welcome',
      type: NotificationType.system,
      title: 'Welcome to ${AppConfig.appName}',
      subtitle:
          'Alerts for price spikes, low margins, and reminders will appear here.',
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      actionRoute: '/home',
    ),
  ];

  int get unreadCount => state.where((e) => !e.isRead).length;

  void markRead(String id) {
    state = [
      for (final n in state)
        if (n.id == id)
          NotificationItem(
            id: n.id,
            type: n.type,
            title: n.title,
            subtitle: n.subtitle,
            createdAt: n.createdAt,
            isRead: true,
            actionRoute: n.actionRoute,
          )
        else
          n,
    ];
  }

  void dismiss(String id) {
    state = state.where((n) => n.id != id).toList();
  }

  void addPriceSpikeAlert({required String itemSample}) {
    final id = 'spike_${DateTime.now().millisecondsSinceEpoch}';
    state = [
      NotificationItem(
        id: id,
        type: NotificationType.priceAlert,
        title: 'Price spike',
        subtitle:
            '$itemSample — landing 15%+ above recent average. Verify before next buy.',
        createdAt: DateTime.now(),
        actionRoute: '/purchase',
      ),
      ...state,
    ];
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<NotificationItem>>((ref) {
  return NotificationsNotifier();
});

final notificationsUnreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).where((e) => !e.isRead).length;
});
