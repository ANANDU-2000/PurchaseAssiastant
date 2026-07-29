import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/widgets.dart' show ScrollNotification;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../auth/auth_failure_policy.dart';
import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import '../json_coerce.dart';
import '../navigation/surface_refresh_policy.dart' show kStockListCacheTtl;
import '../../features/shell/shell_branch_provider.dart';
import '../../features/staff/staff_shell_branch_provider.dart';
import 'api_read_snapshots.dart';
import 'app_period_provider.dart';
import 'home_dashboard_provider.dart'
    show
        HomePeriod,
        homePeriodRange,
        homePeriodProvider,
        homeBundledStockStatusCounts,
        homeLowStockDetailFetchEnabledProvider,
        lowStockDashboardMountedProvider;
import '../providers/analytics_kpi_provider.dart' show analyticsDateRangeProvider;
import 'stock_list_exceptions.dart';
import '../utils/stock_audit_rows.dart';

final Map<String, Future<Map<String, dynamic>>> _stockListInflight = {};
final Map<String, Future<Map<String, dynamic>>> _deliveryCountsInflight = {};
final Map<String, Future<Map<String, dynamic>>> _stockAlertsSummaryInflight = {};

/// True when the owner Stock tab or staff Stock tab is the active IndexedStack branch.
bool stockShellTabIsVisible(dynamic ref) {
  if (ref.watch(shellCurrentBranchProvider) == ShellBranch.stock) return true;
  if (ref.watch(staffShellCurrentBranchProvider) == StaffShellBranch.stock) {
    return true;
  }
  return false;
}

/// Query for GET `/v1/businesses/{id}/stock/list`.
class StockListQuery {
  const StockListQuery({
    this.page = 1,
    this.perPage = 50,
    this.q = '',
    this.category = '',
    this.subcategory = '',
    this.supplier = '',
    this.status = 'all',
    this.sort = 'recent',
    this.includePeriod = false,
    this.periodStart,
    this.periodEnd,
    this.purchasedInPeriod = false,
  });

  final int page;
  final int perPage;
  final String q;
  final String category;
  final String subcategory;

  /// Client-side filter on `supplier_name` in list rows (API has no supplier param).
  final String supplier;

  /// `all` | `healthy` | `low` | `critical` | `out`
  final String status;

  /// `name` | `stock_asc` | `stock_desc` | `recent`
  final String sort;

  final bool includePeriod;
  final String? periodStart;
  final String? periodEnd;

  /// Server-side: only items with period purchases (requires [includePeriod]).
  final bool purchasedInPeriod;

  /// Stable cache/dedupe key for list fetches (all query params except supplier).
  String toCacheKey() =>
      '$page|$perPage|$q|$category|$subcategory|'
      '$status|$sort|$includePeriod|$periodStart|$periodEnd|$purchasedInPeriod';

  StockListQuery copyWith({
    int? page,
    int? perPage,
    String? q,
    String? category,
    String? subcategory,
    String? supplier,
    String? status,
    String? sort,
    bool? includePeriod,
    String? periodStart,
    String? periodEnd,
    bool? purchasedInPeriod,
  }) {
    return StockListQuery(
      page: page ?? this.page,
      perPage: perPage ?? this.perPage,
      q: q ?? this.q,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      supplier: supplier ?? this.supplier,
      status: status ?? this.status,
      sort: sort ?? this.sort,
      includePeriod: includePeriod ?? this.includePeriod,
      periodStart: periodStart ?? this.periodStart,
      periodEnd: periodEnd ?? this.periodEnd,
      purchasedInPeriod: purchasedInPeriod ?? this.purchasedInPeriod,
    );
  }
}

/// Home out-of-stock strip — small scoped list (not the stock page query).
const kHomeOutOfStockListQuery = StockListQuery(
  status: 'out',
  perPage: 8,
  page: 1,
  sort: 'stock_asc',
);

final homeOutOfStockListProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return {'items': <Map<String, dynamic>>[], 'total': 0};
  }
  final result = await ref.read(hexaApiProvider).listStock(
        businessId: session.primaryBusiness.id,
        page: kHomeOutOfStockListQuery.page,
        perPage: kHomeOutOfStockListQuery.perPage,
        status: kHomeOutOfStockListQuery.status,
        sort: kHomeOutOfStockListQuery.sort,
      ).timeout(const Duration(seconds: 15));
  if (providerWasDisposed(disposed)) {
    return {'items': <Map<String, dynamic>>[], 'total': 0};
  }
  return result;
});

final stockListQueryProvider =
    StateProvider<StockListQuery>((_) => const StockListQuery());

/// Last successful `/stock/list` ETag + body (page 1, current query fingerprint).
final stockListEtagProvider = StateProvider<String?>((ref) => null);
final stockListCachedBodyProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);
final stockListCacheQueryKeyProvider = StateProvider<String?>((ref) => null);

/// Last successful stock list fetch (page 1 ETag path) — gates shell tab refresh.
final stockListLastFetchedAtProvider = StateProvider<DateTime?>((ref) => null);

void clearStockListEtagCache(dynamic ref) {
  ref.read(stockListEtagProvider.notifier).state = null;
  ref.read(stockListCachedBodyProvider.notifier).state = null;
  ref.read(stockListCacheQueryKeyProvider.notifier).state = null;
  ref.read(stockListLastFetchedAtProvider.notifier).state = null;
  ref.read(stockListLiveSnapshotProvider.notifier).state = null;
}

/// Reactive last good page-1 list — UI watches this so 200 + cache write always repaints.
final stockListLiveSnapshotProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

/// Stock list period chips (Today / Week / Month / Year).
final stockPagePeriodProvider =
    StateProvider<HomePeriod>((_) => HomePeriod.allTime);

/// Tablet/desktop split pane selection.
final stockSelectedItemIdProvider = StateProvider<String?>((ref) => null);

/// Restored scroll position when returning to the stock list tab.
final stockListScrollOffsetProvider = StateProvider<double>((ref) => 0);

enum StockDeliveryFilter { all, pending, delivered }

/// Client-side delivery truck filter on stock list.
final stockDeliveryFilterProvider =
    StateProvider<StockDeliveryFilter>((ref) => StockDeliveryFilter.all);

/// True when list query narrows beyond default warehouse scope (search, period, etc.).
bool stockListHasScopedFilters(StockListQuery q, StockOperationalFilters op) {
  if (q.q.trim().isNotEmpty) return true;
  if (q.category.trim().isNotEmpty) return true;
  if (q.supplier.trim().isNotEmpty) return true;
  if (q.purchasedInPeriod) return true;
  if (op.evictionOnly) return true;
  if (op.purchasedInPeriodOnly) return true;
  return false;
}

/// RAM ETag cache must not replay an empty page-1 payload (dispose/auth race artifact).
bool stockListCacheBodyIsUsable(Map<String, dynamic>? body) {
  if (body == null || body.isEmpty) return false;
  if (body['_not_modified'] == true) return false;
  final total = coerceToInt(body['total']);
  if (total > 0) return true;
  final items = body['items'];
  return items is List && items.isNotEmpty;
}

/// Last successful page-1 body for the active query (survives autoDispose races on web).
Map<String, dynamic>? stockListCachedDataForCurrentQuery(dynamic ref) {
  final queryKey = ref.read(stockListQueryProvider).toCacheKey();
  final live = ref.read(stockListLiveSnapshotProvider);
  if (live != null && stockListCacheBodyIsUsable(live)) {
    final liveKey = ref.read(stockListCacheQueryKeyProvider);
    if (liveKey == queryKey) return Map<String, dynamic>.from(live);
  }
  final cacheKey = ref.read(stockListCacheQueryKeyProvider);
  if (cacheKey != queryKey) return null;
  final cached = ref.read(stockListCachedBodyProvider);
  if (!stockListCacheBodyIsUsable(cached)) return null;
  if (cached == null) return null;
  return Map<String, dynamic>.from(cached);
}

void _writeStockListRamCache(
  dynamic ref, {
  required Map<String, dynamic> next,
  required StockListQuery query,
  required String queryKey,
  required Map<String, dynamic> res,
}) {
  Future.microtask(() {
    try {
      final newEtag = res['_etag']?.toString();
      if (query.page == 1 && stockListCacheBodyIsUsable(next)) {
        if (newEtag != null && newEtag.isNotEmpty) {
          ref.read(stockListEtagProvider.notifier).state = newEtag;
        }
        ref.read(stockListCachedBodyProvider.notifier).state = next;
        ref.read(stockListCacheQueryKeyProvider.notifier).state = queryKey;
        ref.read(stockListLastFetchedAtProvider.notifier).state = DateTime.now();
        ref.read(stockListLiveSnapshotProvider.notifier).state = next;
      } else if (query.page == 1 && res['_not_modified'] != true) {
        ref.read(stockListLastFetchedAtProvider.notifier).state = DateTime.now();
      }
    } catch (_) {
    }
  });
}

int _warehouseChipFilterCount(StockListQuery q, StockOperationalFilters op) {
  var n = 0;
  if (q.subcategory.isNotEmpty) n++;
  if (q.status != 'all') n++;
  if (op.missingBarcodeOnly) n++;
  if (op.missingItemCodeOnly) n++;
  if (op.reorderOnly) n++;
  if (op.unit.isNotEmpty) n++;
  return n;
}

/// Client-side filters shared by stock + bulk print.
class StockOperationalFilters {
  const StockOperationalFilters({
    this.missingBarcodeOnly = false,
    this.missingItemCodeOnly = false,
    this.reorderOnly = false,
    this.evictionOnly = false,
    this.purchasedInPeriodOnly = false,
    this.unit = '',
  });

  final bool missingBarcodeOnly;
  final bool missingItemCodeOnly;
  final bool reorderOnly;
  final bool evictionOnly;
  final bool purchasedInPeriodOnly;

  /// Empty = all units; else match `unit` field lowercased.
  final String unit;

  StockOperationalFilters copyWith({
    bool? missingBarcodeOnly,
    bool? missingItemCodeOnly,
    bool? reorderOnly,
    bool? evictionOnly,
    bool? purchasedInPeriodOnly,
    String? unit,
    bool clearUnit = false,
    bool clearMissingItemCode = false,
    bool clearEviction = false,
  }) {
    return StockOperationalFilters(
      missingBarcodeOnly: missingBarcodeOnly ?? this.missingBarcodeOnly,
      missingItemCodeOnly: clearMissingItemCode
          ? false
          : (missingItemCodeOnly ?? this.missingItemCodeOnly),
      reorderOnly: reorderOnly ?? this.reorderOnly,
      evictionOnly: clearEviction ? false : (evictionOnly ?? this.evictionOnly),
      purchasedInPeriodOnly:
          purchasedInPeriodOnly ?? this.purchasedInPeriodOnly,
      unit: clearUnit ? '' : (unit ?? this.unit),
    );
  }
}

final stockOperationalFiltersProvider = StateProvider<StockOperationalFilters>(
    (_) => const StockOperationalFilters());

/// Selected row for bulk print desktop preview panel.
final bulkPreviewItemIdProvider = StateProvider<String?>((ref) => null);

int countOperationalActiveFilters(
    StockListQuery q, StockOperationalFilters op) {
  var n = 0;
  if (q.category.isNotEmpty) n++;
  if (q.subcategory.isNotEmpty) n++;
  if (q.supplier.isNotEmpty) n++;
  if (q.status != 'all') n++;
  if (q.sort != 'recent') n++;
  if (op.missingBarcodeOnly) n++;
  if (op.missingItemCodeOnly) n++;
  if (op.reorderOnly) n++;
  if (op.evictionOnly) n++;
  if (op.purchasedInPeriodOnly) n++;
  if (op.unit.isNotEmpty) n++;
  return n;
}

/// On-hand warehouse totals (bags/kg/boxes/tins). Never pass period — that returns purchases.
final stockOnHandTotalsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 3));
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final totals = await ref.read(hexaApiProvider).getStockTotals(
        businessId: session.primaryBusiness.id,
      ).timeout(const Duration(seconds: 15));
  if (providerWasDisposed(disposed)) return {};
  return totals;
});

/// Purchased qty totals for [period] (used when comparing to on-hand).
final stockTotalsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, AppPeriod>(
  (ref, period) async {
    final disposed = registerProviderDisposeGuard(ref);
    registerProviderKeepAliveTimer(ref, const Duration(minutes: 3));
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    final totals = await ref.read(hexaApiProvider).getStockTotals(
          businessId: session.primaryBusiness.id,
          periodStart: appPeriodApiDateFrom(ref, period),
          periodEnd: appPeriodApiDateTo(ref, period),
        ).timeout(const Duration(seconds: 15));
    if (providerWasDisposed(disposed)) return {};
    return totals;
  },
);

/// True when the Stock **Activity** tab is visible (lazy-load audit feed).
final stockChangesTabActiveProvider = StateProvider<bool>((ref) => false);

/// Bundled Stock tab cold load — replaces parallel list/summary/delivery GETs on page 1.
final stockShellBundleProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 30));
  // IndexedStack keeps Stock mounted off-tab — skip network until visible.
  if (!stockShellTabIsVisible(ref)) {
    return const {};
  }
  final session = ref.watch(sessionProvider);
  if (session == null || providerSkipApi(ref)) return const {};
  final query = ref.watch(stockListQueryProvider);
  if (query.page != 1) return const {};
  final op = ref.watch(stockOperationalFiltersProvider);
  final purchasedInPeriod = query.purchasedInPeriod || op.purchasedInPeriodOnly;
  final api = ref.read(hexaApiProvider);
  final bundle = await api.fetchStockShellBundle(
    businessId: session.primaryBusiness.id,
    page: query.page,
    perPage: query.perPage,
    q: query.q,
    category: query.category,
    subcategory: query.subcategory,
    status: query.status,
    sort: query.sort,
    includePeriod: query.includePeriod,
    periodStart: query.periodStart,
    periodEnd: query.periodEnd,
    purchasedInPeriod: purchasedInPeriod,
    missingBarcode: op.missingBarcodeOnly,
    missingItemCode: op.missingItemCodeOnly,
    reorderOnly: op.reorderOnly,
    unit: op.unit,
  ).timeout(const Duration(seconds: 30));
  if (providerWasDisposed(disposed)) return const {};
  return bundle;
});

/// Stock audit events for the stock page **Changes** tab (newest first).
/// Reads [stockAuditRecentSnapshotProvider] — no extra HTTP when home already loaded audit.
final stockChangesFeedProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  ref.watch(stockPagePeriodProvider);
  if (!ref.watch(stockChangesTabActiveProvider)) {
    return const [];
  }
  final rows = await ref.watch(stockAuditRecentSnapshotProvider.future);
  if (providerWasDisposed(disposed)) return [];
  final period = ref.read(stockPagePeriodProvider);
  // Prefer `updated_at` (API StockAdjustmentOut) via shared helpers — filtering
  // only on `created_at` left the Activity tab empty on desktop/web.
  return sortStockAuditRowsNewestFirst(
    filterStockAuditRowsByHomePeriod(rows, period),
  );
});

Map<String, dynamic> _stockListFinalizePayload(
  Map<String, dynamic> res,
  dynamic ref, {
  required StockListQuery query,
  required String queryKey,
  required ProviderDisposeGuard disposed,
}) {
  final next = Map<String, dynamic>.from(res)..remove('_etag');
  _writeStockListRamCache(
    ref,
    next: next,
    query: query,
    queryKey: queryKey,
    res: res,
  );
  return next;
}

/// Kept alive (not autoDispose) — web IndexedStack + dispose races caused 200 + skeleton forever.
final stockListProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final keepAliveLink = ref.keepAlive();
  final keepAliveTimer = Timer(kStockListCacheTtl, keepAliveLink.close);
  ref.onDispose(keepAliveTimer.cancel);
  final session = ref.watch(sessionProvider);
  final query = ref.watch(stockListQueryProvider);
  if (session == null) {
    throw const StockListFetchBlockedException('no_session');
  }
  // Off-tab: serve RAM cache only — History/Reports already gate this way.
  if (!stockShellTabIsVisible(ref)) {
    final cachedBody = ref.read(stockListCachedBodyProvider);
    if (stockListCacheBodyIsUsable(cachedBody) && cachedBody != null) {
      return Map<String, dynamic>.from(cachedBody);
    }
    // Prefer empty payload over a blocking exception so IndexedStack paint stays calm.
    return const <String, dynamic>{
      'items': <dynamic>[],
      'total': 0,
      'page': 1,
      'per_page': 50,
    };
  }
  if (!kIsWeb) {
    await awaitProviderApiReady(ref);
  }
  final skipApi = providerSkipApi(ref);
  if (skipApi) {
    final cachedBody = ref.read(stockListCachedBodyProvider);
    if (stockListCacheBodyIsUsable(cachedBody) && cachedBody != null) {
      return Map<String, dynamic>.from(cachedBody);
    }
    final canForceLiveOnWeb = kIsWeb &&
        !ref.read(auth401CircuitOpenProvider) &&
        !ref.read(authSessionExpiredProvider);
    if (!canForceLiveOnWeb) {
      throw const StockListFetchBlockedException('api_gate');
    }
  }
  final queryKey = query.toCacheKey();
  final cachedKey = ref.read(stockListCacheQueryKeyProvider);
  final cachedBody = ref.read(stockListCachedBodyProvider);
  final etag = ref.read(stockListEtagProvider);
  final useEtag =
      !kIsWeb && query.page == 1 && cachedKey == queryKey && etag != null;
  final bid = session.primaryBusiness.id;
  final purchasedInPeriod = query.purchasedInPeriod ||
      ref.read(stockOperationalFiltersProvider).purchasedInPeriodOnly;

  if (query.page == 1) {
    final bundleAsync = ref.watch(stockShellBundleProvider);
    if (bundleAsync.isLoading) {
      try {
        final bundle = await ref.read(stockShellBundleProvider.future);
        final list = bundle['list'];
        if (list is Map) {
          final res = Map<String, dynamic>.from(list);
          _writeStockListRamCache(
            ref,
            next: res,
            query: query,
            queryKey: queryKey,
            res: res,
          );
          return res;
        }
      } catch (_) {
      }
    } else if (bundleAsync.hasValue) {
      final list = bundleAsync.value?['list'];
      if (list is Map) {
        final res = Map<String, dynamic>.from(list);
        _writeStockListRamCache(
          ref,
          next: res,
          query: query,
          queryKey: queryKey,
          res: res,
        );
        return res;
      }
    }
  }

  final inflightKey =
      '$bid|$queryKey|${useEtag ? etag : ''}|$purchasedInPeriod';
  final api = ref.read(hexaApiProvider);

  Map<String, dynamic> res;
  try {
    res = await _stockListInflight.putIfAbsent(
      inflightKey,
      () => api
          .listStock(
            businessId: bid,
            page: query.page,
            perPage: query.perPage,
            q: query.q,
            category: query.category,
            subcategory: query.subcategory,
            status: query.status,
            sort: query.sort,
            includePeriod: query.includePeriod,
            periodStart: query.periodStart,
            periodEnd: query.periodEnd,
            purchasedInPeriod: purchasedInPeriod,
            ifNoneMatch: useEtag ? etag : null,
          )
          .whenComplete(() => _stockListInflight.remove(inflightKey)),
    );
  } on DioException {
    if (providerWasDisposed(disposed)) {
      if (stockListCacheBodyIsUsable(cachedBody) && cachedBody != null) {
        return Map<String, dynamic>.from(cachedBody);
      }
      throw const ProviderFetchAborted();
    }
    rethrow;
  }

  if (res['_not_modified'] == true) {
    if (stockListCacheBodyIsUsable(cachedBody) && cachedBody != null) {
      return Map<String, dynamic>.from(cachedBody);
    }
    clearStockListEtagCache(ref);
    res = await api.listStock(
      businessId: bid,
      page: query.page,
      perPage: query.perPage,
      q: query.q,
      category: query.category,
      subcategory: query.subcategory,
      status: query.status,
      sort: query.sort,
      includePeriod: query.includePeriod,
      periodStart: query.periodStart,
      periodEnd: query.periodEnd,
      purchasedInPeriod: purchasedInPeriod,
    );
    if (res['_not_modified'] == true) {
      clearStockListEtagCache(ref);
      throw const StockListFetchBlockedException('etag_stale');
    }
  }

  final finalized = _stockListFinalizePayload(
    res,
    ref,
    query: query,
    queryKey: queryKey,
    disposed: disposed,
  );
  return finalized;
});

/// Loads **all** stock rows matching [stockListQueryProvider] filters (paged API calls).
/// Used by bulk barcode print so the list is not limited to the stock screen page size.
final bulkBarcodeSelectionProvider = StateProvider<Set<String>>((ref) => {});

/// Item ids successfully downloaded/printed this session (bulk barcode page).
final bulkBarcodeDownloadedIdsProvider =
    StateProvider<Set<String>>((ref) => {});

/// Web lazy pagination cap for [bulkStockListProvider] (mobile loads up to 40 pages).
final bulkStockListMaxPageProvider = StateProvider<int>(
  (ref) => kIsWeb ? 1 : 40,
);

/// Request the next bulk stock list page (no-op when already at cap).
void requestBulkStockListNextPage(dynamic ref) {
  final cur = ref.read(bulkStockListMaxPageProvider);
  if (cur >= 40) return;
  ref.read(bulkStockListMaxPageProvider.notifier).state = cur + 1;
}

/// Lazy-load more bulk stock rows when the user scrolls near the list bottom.
bool handleBulkStockListScrollNotification(
  ScrollNotification notification,
  dynamic ref,
  Map<String, dynamic>? blob,
) {
  if (blob?['hasMore'] != true) return false;
  if (blob?['fetchFailed'] == true) return false;
  if (notification.metrics.pixels <
      notification.metrics.maxScrollExtent - 300) {
    return false;
  }
  requestBulkStockListNextPage(ref);
  return false;
}

final bulkStockListProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  final query = ref.watch(stockListQueryProvider);
  final maxPages = ref.watch(bulkStockListMaxPageProvider);
  if (session == null) {
    return {'items': <Map<String, dynamic>>[], 'total': 0, 'loaded': 0};
  }
  final api = ref.read(hexaApiProvider);
  final cancelToken = CancelToken();
  safeRefOnDispose(ref, () {
    if (!cancelToken.isCancelled) cancelToken.cancel('bulk_stock_disposed');
  });
  final pageSize = kIsWeb ? 50 : 500;
  var page = 1;
  final merged = <Map<String, dynamic>>[];
  var total = 0;
  while (page <= maxPages) {
    try {
      final res = await api.listStock(
        businessId: session.primaryBusiness.id,
        page: page,
        perPage: pageSize,
        q: query.q,
        category: query.category,
        subcategory: query.subcategory,
        status: query.status,
        sort: query.sort,
        includePeriod: query.includePeriod,
        periodStart: query.periodStart,
        periodEnd: query.periodEnd,
      ).timeout(const Duration(seconds: 30));
      if (providerWasDisposed(disposed)) {
        return {
          'items': merged,
          'total': total > 0 ? total : merged.length,
          'loaded': merged.length,
          'hasMore': total > merged.length,
        };
      }
      total = (res['total'] as num?)?.toInt() ?? 0;
      final raw = (res['items'] as List?) ?? const [];
      if (raw.isEmpty) break;
      for (final e in raw) {
        if (e is Map) merged.add(Map<String, dynamic>.from(e));
      }
      if (merged.length >= total) break;
      page++;
    } on DioException {
      if (merged.isNotEmpty) {
        return {
          'items': merged,
          'total': total > 0 ? total : merged.length,
          'loaded': merged.length,
          'hasMore': total > merged.length,
          'fetchFailed': true,
        };
      }
      rethrow;
    }
  }
  final hasMore = total > merged.length;
  return {
    'items': merged,
    'total': total,
    'loaded': merged.length,
    if (hasMore) 'hasMore': true,
  };
});

/// Optimistic list-row overlays until the next `/stock/list` fetch replaces them.
final stockListRowPatchProvider =
    StateProvider<Map<String, Map<String, dynamic>>>((ref) => const {});

void _patchStockListSnapshot(
  dynamic ref,
  String itemId,
  Map<String, dynamic> patch,
) {
  void patchProvider(StateProvider<Map<String, dynamic>?> provider) {
    final current = ref.read(provider);
    if (current == null) return;
    final rawItems = current['items'];
    if (rawItems is! List) return;
    var changed = false;
    final items = <Map<String, dynamic>>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final row = Map<String, dynamic>.from(raw);
      if (row['id']?.toString() == itemId) {
        items.add({...row, ...patch});
        changed = true;
      } else {
        items.add(row);
      }
    }
    if (!changed) return;
    ref.read(provider.notifier).state = {...current, 'items': items};
  }

  patchProvider(stockListCachedBodyProvider);
  patchProvider(stockListLiveSnapshotProvider);
}

final Map<String, int> _itemPatchSeq = {};
int _globalPatchSeq = 0;

int captureItemPatchSeq(String itemId) {
  return _itemPatchSeq[itemId] ?? 0;
}

void applyStockListRowPatch(
  dynamic ref, {
  required String itemId,
  required Map<String, dynamic> patch,
}) {
  if (itemId.isEmpty || patch.isEmpty) return;
  final seq = ++_globalPatchSeq;
  _itemPatchSeq[itemId] = seq;
  ref.read(stockListRowPatchProvider.notifier).update(
    (Map<String, Map<String, dynamic>> current) {
      return <String, Map<String, dynamic>>{
        ...current,
        itemId: <String, dynamic>{...?current[itemId], ...patch},
      };
    },
  );
  _patchStockListSnapshot(ref, itemId, patch);
  if (kDebugMode) {
    debugPrint(
      '[STOCK_UI_REFRESH] itemId=$itemId patchKeys=${patch.keys.toList()} seq=$seq',
    );
  }
}

/// Clear row overlays after `/stock/list` returns authoritative server rows.
///
/// Only drops a patch when the server row already reflects it (or is newer via
/// [stock_version]). Blind-clearing every id on the page wiped optimistic
/// SYS/PHYS/DIFF cells when a deferred list refetch returned stale payload.
void reconcileStockListRowPatches(
  dynamic ref,
  Iterable<Map<String, dynamic>> serverRows,
) {
  final patches = ref.read(stockListRowPatchProvider);
  if (patches.isEmpty) return;
  final byId = <String, Map<String, dynamic>>{};
  for (final row in serverRows) {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) continue;
    byId[id] = row;
  }
  if (byId.isEmpty) return;

  final clearIds = <String>[];
  for (final entry in patches.entries) {
    final server = byId[entry.key];
    if (server == null) continue;
    if (_shouldClearStockListRowPatch(server, entry.value)) {
      clearIds.add(entry.key);
    }
  }
  if (clearIds.isNotEmpty) {
    clearStockListRowPatchesForIds(ref, clearIds);
  }
}

bool _shouldClearStockListRowPatch(
  Map<String, dynamic> server,
  Map<String, dynamic> patch,
) {
  if (patch.isEmpty) return true;
  final serverVersion = coerceToDoubleNullable(server['stock_version']);
  final patchVersion = coerceToDoubleNullable(patch['stock_version']);
  // Authoritative list row is strictly newer than the overlay.
  if (serverVersion != null &&
      patchVersion != null &&
      serverVersion > patchVersion) {
    return true;
  }
  return _serverRowReflectsStockListPatch(server, patch);
}

bool _serverRowReflectsStockListPatch(
  Map<String, dynamic> server,
  Map<String, dynamic> patch,
) {
  const keys = <String>[
    'current_stock',
    'physical_stock_qty',
    'physical_stock_difference_qty',
    'stock_status',
    'stock_version',
  ];
  for (final key in keys) {
    if (!patch.containsKey(key)) continue;
    final p = patch[key];
    final s = server[key];
    if (p is num || s is num) {
      final pn = coerceToDoubleNullable(p);
      final sn = coerceToDoubleNullable(s);
      if (pn == null || sn == null) return false;
      if ((pn - sn).abs() > 0.001) return false;
      continue;
    }
    if ('$p' != '$s') return false;
  }
  return true;
}
void clearStockListRowPatchesForIds(
  dynamic ref,
  Iterable<String> itemIds,
) {
  final ids = itemIds.where((id) => id.isNotEmpty).toSet();
  if (ids.isEmpty) return;
  ref.read(stockListRowPatchProvider.notifier).update(
    (Map<String, Map<String, dynamic>> current) {
      final next = Map<String, Map<String, dynamic>>.from(current);
      for (final id in ids) {
        next.remove(id);
      }
      return next;
    },
  );
}

Map<String, int> _stockStatusCountsFromAlertsSummary(
  Map<String, dynamic> summary, {
  int? allTotal,
}) {
  final outCount = (summary['active_out_of_stock'] as num?)?.toInt() ??
      (summary['out_of_stock'] as num?)?.toInt() ??
      0;
  final resolvedAll = allTotal ??
      (summary['total_items'] as num?)?.toInt();
  return {
    'all': resolvedAll ?? 0,
    'low': (summary['low_stock'] as num?)?.toInt() ?? 0,
    'critical': (summary['critical_stock'] as num?)?.toInt() ?? 0,
    'out': outCount,
    'missing_code': (summary['missing_item_code'] as num?)?.toInt() ?? 0,
    'missing_barcode': (summary['missing_barcode'] as num?)?.toInt() ?? 0,
  };
}

/// Status bucket counts for stock filter chips (authoritative server summary).
final stockStatusCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  final bundled = homeBundledStockStatusCounts(ref);
  if (bundled != null) return bundled;
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;

  final summary = await ref.watch(stockAlertsSummaryProvider.future);
  if (providerWasDisposed(disposed)) return {};
  final allTotal = (summary['total_items'] as num?)?.toInt();
  if (allTotal != null && allTotal > 0) {
    return _stockStatusCountsFromAlertsSummary(summary, allTotal: allTotal);
  }

  final res = await api.listStock(
    businessId: bid,
    page: 1,
    perPage: 1,
    status: 'all',
    sort: 'recent',
  ).timeout(const Duration(seconds: 15));
  if (providerWasDisposed(disposed)) return {};
  return _stockStatusCountsFromAlertsSummary(
    summary,
    allTotal: (res['total'] as num?)?.toInt() ?? 0,
  );
});

/// Pending/delivered truck counts for stock list filter chips.
final stockDeliveryIndicatorCountsProvider = FutureProvider.autoDispose<
    ({int pending, int delivered})>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 25));
  final session = ref.watch(sessionProvider);
  if (session == null || providerSkipApi(ref)) {
    return (pending: 0, delivered: 0);
  }
  final query = ref.watch(stockListQueryProvider);
  if (query.page == 1) {
    final bundle = ref.watch(stockShellBundleProvider);
    if (bundle.hasValue) {
      final raw = bundle.value?['delivery_counts'];
      if (raw is Map) {
        return (
          pending: (raw['pending'] as num?)?.toInt() ?? 0,
          delivered: (raw['delivered'] as num?)?.toInt() ?? 0,
        );
      }
    }
  }
  final op = ref.watch(stockOperationalFiltersProvider);
  final bid = session.primaryBusiness.id;
  final inflightKey =
      '$bid|${query.toCacheKey()}|${op.missingBarcodeOnly}|${op.missingItemCodeOnly}|'
      '${op.reorderOnly}|${op.unit}';
  final api = ref.read(hexaApiProvider);
  final counts = await _deliveryCountsInflight.putIfAbsent(
    inflightKey,
    () => api
        .stockDeliveryIndicatorCounts(
          businessId: bid,
          q: query.q,
          category: query.category,
          subcategory: query.subcategory,
          status: query.status,
          sort: query.sort,
          includePeriod: query.includePeriod,
          periodStart: query.periodStart,
          periodEnd: query.periodEnd,
          missingBarcode: op.missingBarcodeOnly,
          missingItemCode: op.missingItemCodeOnly,
          reorderOnly: op.reorderOnly,
          unit: op.unit,
        )
        .whenComplete(() => _deliveryCountsInflight.remove(inflightKey)),
  );
  if (providerWasDisposed(disposed)) return (pending: 0, delivered: 0);
  return (
    pending: coerceToInt(counts['pending']),
    delivered: coerceToInt(counts['delivered']),
  );
});

/// All/Low/Out chip counts — scoped when warehouse filters are active.
final stockFilteredStatusCountsProvider =
    FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 25));
  final q = ref.watch(stockListQueryProvider);
  final op = ref.watch(stockOperationalFiltersProvider);
  if (_warehouseChipFilterCount(q, op) == 0 &&
      !stockListHasScopedFilters(q, op)) {
    return ref.watch(stockStatusCountsProvider.future);
  }
  final session = ref.watch(sessionProvider);
  if (session == null || providerSkipApi(ref)) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;

  Future<int> totalFor(String status) async {
    final res = await api.listStock(
      businessId: bid,
      page: 1,
      perPage: 1,
      q: q.q,
      category: q.category,
      subcategory: q.subcategory,
      status: status,
      sort: q.sort,
      includePeriod: q.includePeriod,
      periodStart: q.periodStart,
      periodEnd: q.periodEnd,
      purchasedInPeriod: q.purchasedInPeriod || op.purchasedInPeriodOnly,
      missingBarcode: op.missingBarcodeOnly,
      missingItemCode: op.missingItemCodeOnly,
      reorderOnly: op.reorderOnly,
      unit: op.unit,
    );
    return (res['total'] as num?)?.toInt() ?? 0;
  }

  final results = await Future.wait([
    totalFor('all'),
    totalFor('low'),
    totalFor('critical'),
    totalFor('out'),
  ]);
  if (providerWasDisposed(disposed)) return {};
  return {
    'all': results[0],
    'low': results[1],
    'critical': results[2],
    'out': results[3],
  };
});

/// Low-stock items grouped category → subcategory → rows.
typedef LowStockByCategoryMap
    = Map<String, Map<String, List<Map<String, dynamic>>>>;

({String periodStart, String periodEnd}) _lowStockOpsPeriodStrings(Ref ref) {
  final period = ref.watch(homePeriodProvider);
  final customRange = ref.watch(analyticsDateRangeProvider);
  final range = homePeriodRange(
    period,
    now: DateTime.now(),
    custom: period == HomePeriod.custom
        ? (start: customRange.from, endInclusive: customRange.to)
        : null,
  );
  String iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return (periodStart: iso(range.start), periodEnd: iso(range.end));
}

Future<List<Map<String, dynamic>>> _fetchLowStockOperationsAllPages({
  required HexaApi api,
  required String businessId,
  required String periodStart,
  required String periodEnd,
  int maxPages = 10,
}) async {
  var page = 1;
  final merged = <Map<String, dynamic>>[];
  while (page <= maxPages) {
    final res = await api.listLowStockOperations(
      businessId: businessId,
      page: page,
      perPage: 100,
      filter: 'all',
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    final total = (res['total'] as num?)?.toInt() ?? 0;
    final raw = (res['items'] as List?) ?? const [];
    if (raw.isEmpty) break;
    for (final e in raw) {
      if (e is Map) merged.add(Map<String, dynamic>.from(e));
    }
    if (merged.length >= total) break;
    page++;
  }
  return merged;
}

final lowStockByCategoryProvider =
    FutureProvider.autoDispose<LowStockByCategoryMap>((ref) async {
  final mounted = ref.watch(lowStockDashboardMountedProvider);
  if (shellBranchIsVisible(ref, ShellBranch.home) &&
      mounted < 1 &&
      !ref.watch(homeLowStockDetailFetchEnabledProvider)) {
    return {};
  }
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final periods = _lowStockOpsPeriodStrings(ref);
  final lowRows = await _fetchLowStockOperationsAllPages(
    api: api,
    businessId: bid,
    periodStart: periods.periodStart,
    periodEnd: periods.periodEnd,
  );
  if (providerWasDisposed(disposed)) return {};
  final byId = <String, Map<String, dynamic>>{};
  for (final item in lowRows) {
    final id = item['id']?.toString();
    if (id != null && id.isNotEmpty) {
      byId[id] = item;
    } else {
      byId['_${byId.length}'] = item;
    }
  }
  final merged = byId.values.toList();

  final result = <String, Map<String, List<Map<String, dynamic>>>>{};
  for (final item in merged) {
    final cat = item['category_name']?.toString().trim();
    final catKey = (cat != null && cat.isNotEmpty) ? cat : 'Unknown';
    final sub = item['subcategory_name']?.toString().trim();
    final subKey = (sub != null && sub.isNotEmpty) ? sub : 'Other';
    final subMap = result.putIfAbsent(catKey, () => <String, List<Map<String, dynamic>>>{});
    final subList = subMap.putIfAbsent(subKey, () => <Map<String, dynamic>>[]);
    subList.add(item);
  }
  return result;
});

/// Raw GET `/stock/alerts/summary` — SSOT for chip counts off Home bundle.
final stockAlertsSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 30));
  final session = ref.watch(sessionProvider);
  if (session == null || providerSkipApi(ref)) return const {};
  final query = ref.watch(stockListQueryProvider);
  if (query.page == 1) {
    final bundle = ref.watch(stockShellBundleProvider);
    if (bundle.hasValue) {
      final counts = bundle.value?['status_counts'];
      if (counts is Map) {
        return Map<String, dynamic>.from(counts);
      }
    }
  }
  if (providerWasDisposed(disposed)) return const {};
  final bid = session.primaryBusiness.id;
  final summary = await _stockAlertsSummaryInflight.putIfAbsent(
    bid,
    () => ref
        .read(hexaApiProvider)
        .getStockAlertsSummary(businessId: bid)
        .whenComplete(() => _stockAlertsSummaryInflight.remove(bid)),
  );
  if (providerWasDisposed(disposed)) return const {};
  return summary;
});
