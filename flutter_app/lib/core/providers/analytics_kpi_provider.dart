import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';

/// Selected date range for the Analytics tab (inclusive).
/// For the same window as Home, set [from]/[to] to match the snapshot request
/// Inclusive [from]/[to] — use the same YYYY-MM-DD range as the Home trade snapshot
/// (`homeDashboardDataProvider` in `lib/core/providers/home_dashboard_provider.dart`).
final analyticsDateRangeProvider =
    StateProvider<({DateTime from, DateTime to})>((ref) {
  final n = DateTime.now();
  return (
    from: DateTime(n.year, n.month, 1),
    to: DateTime(n.year, n.month, n.day)
  );
});

class AnalyticsKpi {
  const AnalyticsKpi({
    required this.totalPurchase,
    required this.totalQtyBase,
    required this.totalProfit,
    required this.purchaseCount,
    this.totalKg = 0,
    this.totalBags = 0,
    this.totalBoxes = 0,
    this.totalTins = 0,
  });

  final double totalPurchase;
  final double totalQtyBase;
  final double totalProfit;
  final int purchaseCount;
  final double totalKg;
  final double totalBags;
  final double totalBoxes;
  final double totalTins;
}

final analyticsKpiProvider =
    FutureProvider.autoDispose<AnalyticsKpi>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final api = ref.read(hexaApiProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  final m = await api.tradePurchaseSummary(
    businessId: session.primaryBusiness.id,
    from: fmt.format(range.from),
    to: fmt.format(range.to),
  );
  final u = m['unit_totals'];
  Map<String, dynamic> ut = {};
  if (u is Map) {
    ut = Map<String, dynamic>.from(u);
  }
  return AnalyticsKpi(
    totalPurchase: (m['total_purchase'] as num?)?.toDouble() ?? 0,
    totalQtyBase: (m['total_qty'] as num?)?.toDouble() ?? 0,
    totalProfit: 0,
    purchaseCount: (m['deals'] as num?)?.toInt() ?? 0,
    totalKg: (ut['total_kg'] as num?)?.toDouble() ?? 0,
    totalBags: (ut['total_bags'] as num?)?.toDouble() ?? 0,
    totalBoxes: (ut['total_boxes'] as num?)?.toDouble() ?? 0,
    totalTins: (ut['total_tins'] as num?)?.toDouble() ?? 0,
  );
});
