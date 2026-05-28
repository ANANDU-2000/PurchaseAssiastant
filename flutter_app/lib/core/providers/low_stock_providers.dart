import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../providers/analytics_kpi_provider.dart' show analyticsDateRangeProvider;
import '../providers/home_dashboard_provider.dart'
    show HomePeriod, homePeriodRange, homePeriodProvider;

/// Query state for `/stock/low-stock/operations`.
///
/// This intentionally mirrors the operational list controls (q/filter/sort),
/// while pagination stays conservative for mobile-first UX.
class LowStockOperationsQuery {
  const LowStockOperationsQuery({
    this.q = '',
    this.filter = 'all',
    this.page = 1,
    this.perPage = 200,
    this.category = '',
    this.subcategory = '',
    this.sort = 'priority',
  });

  final String q;
  final String filter;
  final int page;
  final int perPage;
  final String category;
  final String subcategory;
  final String sort;

  LowStockOperationsQuery copyWith({
    String? q,
    String? filter,
    int? page,
    int? perPage,
    String? category,
    String? subcategory,
    String? sort,
  }) {
    return LowStockOperationsQuery(
      q: q ?? this.q,
      filter: filter ?? this.filter,
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      sort: sort ?? this.sort,
    );
  }
}

final lowStockOperationsQueryProvider =
    StateProvider<LowStockOperationsQuery>((_) => const LowStockOperationsQuery());

String _periodStartString({required ({DateTime start, DateTime end}) range}) =>
    '${range.start.year}-${range.start.month.toString().padLeft(2, '0')}-${range.start.day.toString().padLeft(2, '0')}';

String _periodEndString({required ({DateTime start, DateTime end}) range}) =>
    '${range.end.year}-${range.end.month.toString().padLeft(2, '0')}-${range.end.day.toString().padLeft(2, '0')}';

({String periodStart, String periodEnd}) _periodStrings(Ref ref) {
  final period = ref.watch(homePeriodProvider);
  final customRange = ref.watch(analyticsDateRangeProvider);
  final range = homePeriodRange(
    period,
    now: DateTime.now(),
    custom: period == HomePeriod.custom
        ? (start: customRange.from, endInclusive: customRange.to)
        : null,
  );
  return (
    periodStart: _periodStartString(range: range),
    periodEnd: _periodEndString(range: range),
  );
}

/// Low-stock KPIs for the operations header.
final lowStockOperationsSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};

  final query = ref.watch(lowStockOperationsQueryProvider);
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final periods = _periodStrings(ref);

  try {
    final result = await api.getLowStockSummary(
      businessId: bid,
      q: query.q,
      category: query.category,
      subcategory: query.subcategory,
      periodStart: periods.periodStart,
      periodEnd: periods.periodEnd,
    );
    if (kDebugMode) {
      debugPrint('[LowStock] Summary response: $result');
    }
    return result;
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[LowStock] Summary error: $e');
    }
    rethrow;
  }
});

/// Low-stock operations list items (priority-sorted v1).
final lowStockOperationsPageProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};

  final query = ref.watch(lowStockOperationsQueryProvider);
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final periods = _periodStrings(ref);

  return api.listLowStockOperations(
    businessId: bid,
    page: query.page,
    perPage: query.perPage,
    q: query.q,
    filter: query.filter,
    category: query.category,
    subcategory: query.subcategory,
    sort: query.sort,
    periodStart: periods.periodStart,
    periodEnd: periods.periodEnd,
  );
});

/// Merged stock activity for low-stock expanded rows / desktop context panel.
final lowStockItemTimelineProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).getStockItemActivity(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
      );
});

