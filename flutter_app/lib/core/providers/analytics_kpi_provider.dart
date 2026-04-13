import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';

/// Selected date range for the Analytics tab (inclusive).
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
  });

  final double totalPurchase;
  final double totalQtyBase;
  final double totalProfit;
  final int purchaseCount;
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
  final m = await api.analyticsSummary(
    businessId: session.primaryBusiness.id,
    from: fmt.format(range.from),
    to: fmt.format(range.to),
  );
  return AnalyticsKpi(
    totalPurchase: (m['total_purchase'] as num?)?.toDouble() ?? 0,
    totalQtyBase: (m['total_qty_base'] as num?)?.toDouble() ?? 0,
    totalProfit: (m['total_profit'] as num?)?.toDouble() ?? 0,
    purchaseCount: (m['purchase_count'] as num?)?.toInt() ?? 0,
  );
});
