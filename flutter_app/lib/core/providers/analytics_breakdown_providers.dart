import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import 'analytics_kpi_provider.dart';

/// One calendar day of summed line profit (for Overview trend chart).
typedef AnalyticsDailyProfitPoint = ({DateTime day, double profit});

/// Last 30 calendar days ending on [analyticsDateRangeProvider].to (inclusive).
final analyticsDailyProfitProvider = FutureProvider.autoDispose<List<AnalyticsDailyProfitPoint>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final end = DateTime(range.to.year, range.to.month, range.to.day);
  final start = end.subtract(const Duration(days: 29));
  final fmt = DateFormat('yyyy-MM-dd');
  final raw = await ref.read(hexaApiProvider).listEntries(
        businessId: session.primaryBusiness.id,
        from: fmt.format(start),
        to: fmt.format(end),
      );
  final byDay = <String, double>{};
  for (final e in raw) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    final ds = m['entry_date']?.toString().split('T').first;
    if (ds == null) continue;
    final lines = m['lines'];
    var p = 0.0;
    if (lines is List) {
      for (final ln in lines) {
        if (ln is! Map) continue;
        p += (Map<String, dynamic>.from(ln)['profit'] as num?)?.toDouble() ?? 0;
      }
    }
    byDay[ds] = (byDay[ds] ?? 0) + p;
  }
  final out = <AnalyticsDailyProfitPoint>[];
  for (var i = 0; i < 30; i++) {
    final d = start.add(Duration(days: i));
    final key = fmt.format(d);
    out.add((day: d, profit: byDay[key] ?? 0));
  }
  return out;
});

final analyticsItemsTableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsItems(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsCategoriesTableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsCategories(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsSuppliersTableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsSuppliers(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});

final analyticsBrokersTableProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return [];
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).analyticsBrokers(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      );
});
