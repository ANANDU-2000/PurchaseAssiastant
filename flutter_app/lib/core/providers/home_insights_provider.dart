import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import 'dashboard_period_provider.dart';

class HomeInsightsData {
  const HomeInsightsData({
    required this.topItem,
    required this.topItemProfit,
    required this.worstItem,
    required this.worstItemProfit,
    required this.bestSupplierName,
    required this.bestSupplierProfit,
    required this.profitChangePctPriorMtd,
    required this.negativeLineCount,
    required this.alertCount,
    required this.alerts,
  });

  final String? topItem;
  final double? topItemProfit;
  final String? worstItem;
  final double? worstItemProfit;
  final String? bestSupplierName;
  final double? bestSupplierProfit;
  final double? profitChangePctPriorMtd;
  final int negativeLineCount;
  final int alertCount;
  final List<Map<String, dynamic>> alerts;
}

final homeInsightsProvider =
    FutureProvider.autoDispose<HomeInsightsData>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  ref.watch(dashboardPeriodProvider);
  final api = ref.read(hexaApiProvider);
  final range = dashboardDateRange(ref.read(dashboardPeriodProvider));
  final fmt = DateFormat('yyyy-MM-dd');
  final m = await api.homeInsights(
    businessId: session.primaryBusiness.id,
    from: fmt.format(range.$1),
    to: fmt.format(range.$2),
  );
  final alerts = (m['alerts'] as List<dynamic>?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ??
      [];
  final topProfit = m['top_item_profit'];
  final worstProfit = m['worst_item_profit'];
  final bestSupProfit = m['best_supplier_profit'];
  final mom = m['profit_change_pct_prior_mtd'];
  return HomeInsightsData(
    topItem: m['top_item'] as String?,
    topItemProfit: (topProfit as num?)?.toDouble(),
    worstItem: m['worst_item'] as String?,
    worstItemProfit: (worstProfit as num?)?.toDouble(),
    bestSupplierName: m['best_supplier_name'] as String?,
    bestSupplierProfit: (bestSupProfit as num?)?.toDouble(),
    profitChangePctPriorMtd: (mom as num?)?.toDouble(),
    negativeLineCount: (m['negative_line_count'] as num?)?.toInt() ?? 0,
    alertCount: alerts.length,
    alerts: alerts,
  );
});
