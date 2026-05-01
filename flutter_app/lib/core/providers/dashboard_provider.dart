import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import '../services/offline_store.dart';
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
  final link = ref.keepAlive();
  Timer(const Duration(minutes: 5), link.close);
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return const DashboardData(
      totalPurchase: 0,
      totalQtyBase: 0,
      totalProfit: 0,
      purchaseCount: 0,
    );
  }
  final period = ref.watch(dashboardPeriodProvider);
  final api = ref.read(hexaApiProvider);
  final range = dashboardDateRange(period);
  final fmt = DateFormat('yyyy-MM-dd');
  final monthFmt = DateFormat('yyyy-MM');
  try {
    final Map<String, dynamic> m;
    if (period == DashboardPeriod.month) {
      final raw = await api.getDashboard(
        businessId: session.primaryBusiness.id,
        month: monthFmt.format(DateTime.now()),
      );
      var qSum = 0.0;
      final items = raw['items'];
      if (items is List) {
        for (final e in items) {
          if (e is Map) {
            qSum += (e['total_qty'] as num?)?.toDouble() ?? 0;
          }
        }
      }
      m = {
        ...raw,
        'total_qty_base': qSum,
      };
    } else {
      m = await api.analyticsSummary(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.$1),
        to: fmt.format(range.$2),
      );
    }
    final map = Map<String, dynamic>.from(m);
    await OfflineStore.cacheDashboardMap(map);
    return DashboardData(
      totalPurchase: (m['total_purchase'] as num?)?.toDouble() ?? 0,
      totalQtyBase: (m['total_qty_base'] as num?)?.toDouble() ?? 0,
      totalProfit: (m['total_profit'] as num?)?.toDouble() ?? 0,
      purchaseCount: (m['purchase_count'] as num?)?.toInt() ?? 0,
    );
  } catch (_) {
    final cached = OfflineStore.getCachedDashboardSummary();
    if (cached != null) {
      return DashboardData(
        totalPurchase: (cached['total_purchase'] as num?)?.toDouble() ?? 0,
        totalQtyBase: (cached['total_qty_base'] as num?)?.toDouble() ?? 0,
        totalProfit: (cached['total_profit'] as num?)?.toDouble() ?? 0,
        purchaseCount: (cached['purchase_count'] as num?)?.toInt() ?? 0,
      );
    }
    rethrow;
  }
});
