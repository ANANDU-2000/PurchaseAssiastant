import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';
import 'analytics_kpi_provider.dart';

/// One calendar day of summed line profit (for Overview trend chart).
typedef AnalyticsDailyProfitPoint = ({DateTime day, double profit});

/// Last 30 calendar days ending on [analyticsDateRangeProvider].to (inclusive).
final analyticsDailyProfitProvider =
    FutureProvider.autoDispose<List<AnalyticsDailyProfitPoint>>((ref) async {
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

/// Last 7 calendar days ending today (local), for Home mini trend chart (independent of analytics date range).
final homeSevenDayProfitProvider =
    FutureProvider.autoDispose<List<AnalyticsDailyProfitPoint>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  final start = end.subtract(const Duration(days: 6));
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
  for (var i = 0; i < 7; i++) {
    final d = start.add(Duration(days: i));
    final key = fmt.format(d);
    out.add((day: d, profit: byDay[key] ?? 0));
  }
  return out;
});

final analyticsItemsTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
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

final analyticsCategoriesTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
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

final analyticsSuppliersTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
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

final analyticsBrokersTableProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
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

/// Heuristic insight: highest estimated purchase-volume item × supplier with lowest avg landing vs peer average.
final analyticsBestSupplierInsightProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final items = await ref.watch(analyticsItemsTableProvider.future);
  final suppliers = await ref.watch(analyticsSuppliersTableProvider.future);
  if (items.isEmpty || suppliers.isEmpty) return null;
  Map<String, dynamic>? topByVol;
  var bestVol = -1.0;
  for (final r in items) {
    final al = (r['avg_landing'] as num?)?.toDouble() ?? 0;
    final tq = (r['total_qty'] as num?)?.toDouble() ?? 0;
    final vol = al * tq;
    if (vol > bestVol) {
      bestVol = vol;
      topByVol = r;
    }
  }
  final itemName = topByVol?['item_name']?.toString() ?? '';
  if (itemName.isEmpty) return null;
  final supList = List<Map<String, dynamic>>.from(suppliers);
  supList.sort((a, b) => ((a['avg_landing'] as num?) ?? 1e18)
      .compareTo((b['avg_landing'] as num?) ?? 1e18));
  final best = supList.first;
  final sname = best['supplier_name']?.toString() ?? '';
  final savg = (best['avg_landing'] as num?)?.toDouble() ?? 0;
  var sum = 0.0;
  for (final s in supList) {
    sum += (s['avg_landing'] as num?)?.toDouble() ?? 0;
  }
  final overall = supList.isEmpty ? savg : sum / supList.length;
  final delta = overall - savg;
  final fmt =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  if (delta.abs() < 0.01) {
    return 'High-volume item: $itemName — $sname has best avg landing (${fmt.format(savg)}) vs peers.';
  }
  return 'Best supplier for $itemName: $sname (${fmt.format(savg)} avg) — ${fmt.format(delta.abs())} ${delta >= 0 ? 'cheaper' : 'higher'} than average landing.';
});
