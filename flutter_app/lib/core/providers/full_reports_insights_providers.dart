import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import 'analytics_kpi_provider.dart';

/// Insights copy block for the full Reports screen (invalidated with other analytics).
final fullReportsInsightsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final range = ref.watch(analyticsDateRangeProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsInsights(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

/// Monthly goals strip on Reports (invalidated with other analytics).
final fullReportsGoalsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;
  final n = DateTime.now();
  final period =
      '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}';
  return ref.read(hexaApiProvider).getAnalyticsGoals(
        businessId: session.primaryBusiness.id,
        period: period,
      );
});
