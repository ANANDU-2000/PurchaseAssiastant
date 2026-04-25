import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/trade_purchase_models.dart';
import 'cloud_expense_provider.dart';
import 'trade_purchases_provider.dart';

enum NotificationType {
  priceAlert,
  profitLow,
  reminder,
  system,
  whatsapp,
  purchaseDue,
  purchaseOverdue,
  cloudCost,
}

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
  final manual = ref.watch(notificationsProvider).where((e) => !e.isRead).length;
  final tradeN = ref.watch(purchaseActionAlertCountProvider);
  final cloudN = ref.watch(cloudCostAlertCountProvider);
  return manual + tradeN + cloudN;
});

/// PUR bills that need attention (unpaid with due date approaching or past).
final purchaseDueAlertItemsProvider =
    Provider<List<NotificationItem>>((ref) {
  final async = ref.watch(tradePurchasesForAlertsProvider);
  return async.maybeWhen(
    data: (rows) {
      final list = <TradePurchase>[];
      for (final row in rows) {
        try {
          list.add(TradePurchase.fromJson(Map<String, dynamic>.from(row)));
        } catch (_) {}
      }
      final out = <NotificationItem>[];
      final today0 = _day0(DateTime.now());
      for (final p in list) {
        if (!_needsPayment(p)) continue;
        final st = p.statusEnum;
        final eff = _effectiveDue(p);
        if (eff != null) {
          if (eff.isBefore(today0)) {
            out.add(NotificationItem(
              id: 'pur_overdue_${p.id}',
              type: NotificationType.purchaseOverdue,
              title: 'Overdue: ${p.humanId}',
              subtitle:
                  '${p.supplierName ?? "—"} · remaining ${_fmtMoney(p.remaining)} (due ${eff.year}-${eff.month.toString().padLeft(2, "0")}-${eff.day.toString().padLeft(2, "0")})',
              createdAt: p.dueDate ?? p.purchaseDate,
              isRead: false,
              actionRoute: '/purchase/detail/${p.id}',
            ));
            continue;
          }
          final days = eff.difference(today0).inDays;
          if (days >= 0 && days <= 5) {
            out.add(NotificationItem(
              id: 'pur_due_${p.id}',
              type: NotificationType.purchaseDue,
              title: 'Payment due: ${p.humanId}',
              subtitle:
                  'Due ${eff.year}-${eff.month.toString().padLeft(2, "0")}-${eff.day.toString().padLeft(2, "0")} · ${_fmtMoney(p.remaining)} left',
              createdAt: eff,
              isRead: false,
              actionRoute: '/purchase/detail/${p.id}',
            ));
            continue;
          }
        }
        if (st == PurchaseStatus.overdue) {
          out.add(NotificationItem(
            id: 'pur_overdue_${p.id}',
            type: NotificationType.purchaseOverdue,
            title: 'Overdue: ${p.humanId}',
            subtitle:
                '${p.supplierName ?? "—"} · remaining ${_fmtMoney(p.remaining)}',
            createdAt: p.dueDate ?? p.purchaseDate,
            isRead: false,
            actionRoute: '/purchase/detail/${p.id}',
          ));
        } else if (st == PurchaseStatus.dueSoon) {
          final due = p.dueDate;
          out.add(NotificationItem(
            id: 'pur_due_${p.id}',
            type: NotificationType.purchaseDue,
            title: 'Payment due: ${p.humanId}',
            subtitle: due != null
                ? 'Due ${due.year}-${due.month.toString().padLeft(2, "0")}-${due.day.toString().padLeft(2, "0")} · ${_fmtMoney(p.remaining)} left'
                : 'Remaining ${_fmtMoney(p.remaining)}',
            createdAt: due ?? p.purchaseDate,
            isRead: false,
            actionRoute: '/purchase/detail/${p.id}',
          ));
        }
      }
      out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return out;
    },
    orElse: () => const [],
  );
});

String _fmtMoney(double n) {
  if (n == n.roundToDouble()) {
    return n.round().toString();
  }
  return n.toStringAsFixed(0);
}

DateTime _day0(DateTime d) => DateTime(d.year, d.month, d.day);

/// Server [dueDate] or `purchaseDate + paymentDays` (local calendar).
DateTime? _effectiveDue(TradePurchase p) {
  if (p.dueDate != null) {
    return _day0(p.dueDate!);
  }
  final n = p.paymentDays;
  if (n == null || n < 0) return null;
  final pd = p.purchaseDate;
  return _day0(pd).add(Duration(days: n));
}

bool _needsPayment(TradePurchase p) {
  if (p.remaining <= 0.01) return false;
  final st = p.statusEnum;
  if (st == PurchaseStatus.paid || st == PurchaseStatus.cancelled) {
    return false;
  }
  return true;
}

/// Client-dismissed purchase-driven alerts (IDs from [purchaseDueAlertItemsProvider]).
final dismissedPurchaseAlertIdsProvider =
    StateProvider<Set<String>>((ref) => {});

final purchaseActionAlertCountProvider = Provider<int>((ref) {
  final all = ref.watch(purchaseDueAlertItemsProvider);
  final dis = ref.watch(dismissedPurchaseAlertIdsProvider);
  return all.where((n) => !dis.contains(n.id)).length;
});

/// 1 if monthly cloud line is due (server `show_alert`).
final cloudCostAlertCountProvider = Provider<int>((ref) {
  final async = ref.watch(cloudCostProvider);
  return async.maybeWhen(
    data: (m) {
      if (m['show_alert'] == true) return 1;
      return 0;
    },
    orElse: () => 0,
  );
});

/// In-app row for the alerts list (when cloud bill is due).
final cloudCostNotificationItemsProvider = Provider<List<NotificationItem>>((ref) {
  final async = ref.watch(cloudCostProvider);
  return async.maybeWhen(
    data: (m) {
      if (m['show_alert'] != true) return [];
      final name = m['name']?.toString() ?? 'Cloud Cost';
      final amt = m['amount_inr'];
      final next = m['next_due_date']?.toString() ?? '—';
      return [
        NotificationItem(
          id: 'cloud_cost_due',
          type: NotificationType.cloudCost,
          title: 'Due: $name',
          subtitle:
              'Rs. ${amt is num ? amt.round() : amt} · due date $next — mark paid in Home or Settings.',
          createdAt: DateTime.now(),
          isRead: false,
          actionRoute: '/settings',
        ),
      ];
    },
    orElse: () => const [],
  );
});
