import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';

class HomeInsightsData {
  const HomeInsightsData({
    required this.topItem,
    required this.topItemProfit,
    required this.alertCount,
    required this.alerts,
  });

  final String? topItem;
  final double? topItemProfit;
  final int alertCount;
  final List<Map<String, dynamic>> alerts;
}

final homeInsightsProvider = FutureProvider.autoDispose<HomeInsightsData>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final api = ref.read(hexaApiProvider);
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, 1);
  final fmt = DateFormat('yyyy-MM-dd');
  final m = await api.homeInsights(
    businessId: session.primaryBusiness.id,
    from: fmt.format(from),
    to: fmt.format(now),
  );
  final alerts = (m['alerts'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  final topProfit = m['top_item_profit'];
  return HomeInsightsData(
    topItem: m['top_item'] as String?,
    topItemProfit: (topProfit as num?)?.toDouble(),
    alertCount: alerts.length,
    alerts: alerts,
  );
});
