import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../models/trade_purchase_models.dart';

/// Bust list + catalog-intel snapshots together.
void invalidateTradePurchaseCaches(dynamic ref) {
  ref.invalidate(tradePurchasesListProvider);
  ref.invalidate(tradePurchasesCatalogIntelProvider);
}

/// Primary history tab for API: `all` | `draft` | `due_soon` | `overdue` | `paid`.
final purchaseHistoryPrimaryFilterProvider =
    StateProvider<String>((ref) => 'all');

/// Client-side filter only (not sent to list API — avoids refetch per keystroke).
final purchaseHistorySearchProvider = StateProvider<String>((ref) => '');

/// Optional secondary chip: `pending` | `paid` | `overdue` (client-side only).
final purchaseHistorySecondaryFilterProvider =
    StateProvider<String?>((ref) => null);

final tradePurchasesListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final primary = ref.watch(purchaseHistoryPrimaryFilterProvider);
  final secondary = ref.watch(purchaseHistorySecondaryFilterProvider);
  final apiStatus = switch (secondary) {
    'overdue' => 'overdue',
    'paid' => 'paid',
    _ => primary,
  };
  return ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
        limit: 200,
        status: apiStatus,
      );
});

/// Parsed rows track [tradePurchasesListProvider] without `await …future`, so
/// async completion cannot call `markNeedsBuild` on a disposed home/shell
/// element after a fast navigation or 401-driven route swap (Riverpod #…).
final tradePurchasesParsedProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  return ref.watch(tradePurchasesListProvider).whenData(
        (maps) => maps
            .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
});

/// Counts for dashboard / history banner.
final purchaseAlertsProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final async = ref.watch(tradePurchasesParsedProvider);
  return async.maybeWhen(
    data: (list) {
      var dueSoon = 0;
      var overdue = 0;
      var paid = 0;
      var dueToday = 0;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (final p in list) {
        final st = p.statusEnum;
        if (st == PurchaseStatus.dueSoon) dueSoon++;
        if (st == PurchaseStatus.overdue) overdue++;
        if (st == PurchaseStatus.paid) paid++;
        if (p.dueDate != null) {
          final d = DateTime(p.dueDate!.year, p.dueDate!.month, p.dueDate!.day);
          if (d == today &&
              st != PurchaseStatus.paid &&
              st != PurchaseStatus.cancelled) {
            dueToday++;
          }
        }
      }
      return {
        'dueSoon': dueSoon,
        'overdue': overdue,
        'paid': paid,
        'dueToday': dueToday,
      };
    },
    orElse: () =>
        {'dueSoon': 0, 'overdue': 0, 'paid': 0, 'dueToday': 0},
  );
});

/// Bags / boxes / tins from loaded trade purchase lines.
final purchaseUnitTotalsProvider =
    Provider.autoDispose<({int bags, int boxes, int tins})>((ref) {
  final async = ref.watch(tradePurchasesParsedProvider);
  return async.maybeWhen(
    data: (list) {
      var bags = 0;
      var boxes = 0;
      var tins = 0;
      for (final p in list) {
        for (final ln in p.lines) {
          final u = ln.unit.toUpperCase();
          final q = ln.qty.round();
          if (u.contains('BAG')) bags += q;
          if (u.contains('BOX')) boxes += q;
          if (u.contains('TIN')) tins += q;
        }
      }
      return (bags: bags, boxes: boxes, tins: tins);
    },
    orElse: () => (bags: 0, boxes: 0, tins: 0),
  );
});

/// Trade list for catalog item intel — always `status=all`, not tied to History
/// tab filters (draft / due_soon chips).
final tradePurchasesCatalogIntelProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
        limit: 200,
        status: 'all',
      );
});

final tradePurchasesCatalogIntelParsedProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  return ref.watch(tradePurchasesCatalogIntelProvider).whenData(
        (maps) => maps
            .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
});
