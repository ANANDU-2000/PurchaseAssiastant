import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import 'dashboard_period_provider.dart';

class DashboardData {
  const DashboardData({
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

final dashboardProvider =
    FutureProvider.autoDispose<DashboardData>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw StateError('No session');
  }
  final period = ref.watch(dashboardPeriodProvider);
  final api = ref.read(hexaApiProvider);
  final range = dashboardDateRange(period);
  final fmt = DateFormat('yyyy-MM-dd');
  final m = await api.analyticsSummary(
    businessId: session.primaryBusiness.id,
    from: fmt.format(range.$1),
    to: fmt.format(range.$2),
  );
  return DashboardData(
    totalPurchase: (m['total_purchase'] as num?)?.toDouble() ?? 0,
    totalQtyBase: (m['total_qty_base'] as num?)?.toDouble() ?? 0,
    totalProfit: (m['total_profit'] as num?)?.toDouble() ?? 0,
    purchaseCount: (m['purchase_count'] as num?)?.toInt() ?? 0,
  );
});
