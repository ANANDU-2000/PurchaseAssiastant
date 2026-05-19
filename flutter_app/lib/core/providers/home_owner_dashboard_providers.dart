import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../json_coerce.dart';
import 'home_dashboard_provider.dart';

String _apiDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Today-only dashboard row for the owner home stats strip (not tied to [homePeriodProvider]).
final homeTodayDashboardDataProvider =
    FutureProvider.autoDispose<HomeDashboardData>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return HomeDashboardData.empty;
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final from = _apiDate(day);
  final to = from;
  final snap = await ref.read(hexaApiProvider).reportsHomeOverview(
        businessId: session.primaryBusiness.id,
        from: from,
        to: to,
        compact: true,
        shellBundle: false,
      );
  return homeDashboardDataFromApiSnapshot(HomePeriod.today, snap);
});

/// Single parallel fetch for low + critical counts (avoids duplicate sequential home polls).
final stockAlertCountsProvider =
    FutureProvider.autoDispose<({int low, int critical})>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return (low: 0, critical: 0);
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final results = await Future.wait([
    api.listStock(businessId: bid, page: 1, perPage: 1, status: 'low'),
    api.listStock(businessId: bid, page: 1, perPage: 1, status: 'critical'),
  ]);
  return (
    low: coerceToInt(results[0]['total']),
    critical: coerceToInt(results[1]['total']),
  );
});

final stockLowCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final c = await ref.watch(stockAlertCountsProvider.future);
  return c.low;
});

final stockCriticalCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final c = await ref.watch(stockAlertCountsProvider.future);
  return c.critical;
});

/// Top low-stock rows (server sorts by stock vs reorder).
final stockLowTopHomeProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final m = await ref.read(hexaApiProvider).listStockLow(
        businessId: session.primaryBusiness.id,
        page: 1,
        perPage: 6,
      );
  final items = m['items'];
  if (items is! List) return [];
  return [
    for (final e in items)
      if (e is Map) Map<String, dynamic>.from(e),
  ];
});

final stockAuditRecentHomeProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listStockAuditRecent(
        businessId: session.primaryBusiness.id,
        limit: 8,
      );
});

/// Stock adjustments for a single calendar day (owner today feed).
final stockAuditDayProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, DateTime>((ref, day) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final d = DateTime(day.year, day.month, day.day);
  return ref.read(hexaApiProvider).listStockAuditRecent(
        businessId: session.primaryBusiness.id,
        limit: 50,
        on: _apiDate(d),
      );
});

final stockVariancesTodayProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listStockVariancesToday(
        businessId: session.primaryBusiness.id,
      );
});

final activeSessionsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return 0;
  final rows = await ref.read(hexaApiProvider).listActiveSessions(
        businessId: session.primaryBusiness.id,
      );
  return rows.length;
});

final homeRecentPurchasesCompactProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final now = DateTime.now();
  final day = DateTime(now.year, now.month, now.day);
  final from = _apiDate(day);
  final rows = await ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
        limit: 6,
        offset: 0,
        status: 'all',
        purchaseFrom: from,
        purchaseTo: from,
      );
  return rows;
});
