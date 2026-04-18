import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../models/trade_purchase_models.dart';

final tradePurchasesListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
      );
});

final tradePurchasesParsedProvider =
    FutureProvider.autoDispose<List<TradePurchase>>((ref) async {
  final maps = await ref.watch(tradePurchasesListProvider.future);
  return maps
      .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
      .toList();
});

/// Counts for dashboard alert strip: overdue, due today, paid.
final purchaseAlertsProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final async = ref.watch(tradePurchasesParsedProvider);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return async.maybeWhen(
    data: (list) {
      var overdue = 0;
      var dueToday = 0;
      var paid = 0;
      for (final p in list) {
        final st = p.statusEnum;
        if (st == PurchaseStatus.overdue) overdue++;
        if (p.dueDate != null) {
          final d = DateTime(p.dueDate!.year, p.dueDate!.month, p.dueDate!.day);
          if (d == today &&
              st != PurchaseStatus.paid &&
              st != PurchaseStatus.cancelled) {
            dueToday++;
          }
        }
        if (st == PurchaseStatus.paid) paid++;
      }
      return {'overdue': overdue, 'dueToday': dueToday, 'paid': paid};
    },
    orElse: () => {'overdue': 0, 'dueToday': 0, 'paid': 0},
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
