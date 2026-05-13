import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../models/trade_purchase_models.dart';
import '../../features/shell/shell_branch_provider.dart';
import 'analytics_kpi_provider.dart' show analyticsDateRangeProvider;
import '../utils/line_display.dart';

/// Alert strip: small cap — full due counts use server-side reports when needed.
const kTradePurchasesAlertFetchLimit = 50;

/// History first page; scroll end loads more via [TradePurchasesListNotifier.loadMore].
const kTradePurchasesHistoryFetchLimit = 100;

String? _purchaseFromApi(DateTime? d) {
  if (d == null) return null;
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// Derives API `status` from history chips / route. [null] means unfiltered (`all`).
String? _tradeListApiStatus(String primaryRaw, String? secondaryRaw) {
  final sec = secondaryRaw?.trim().toLowerCase();
  if (sec == 'overdue') return sec;

  final p = primaryRaw.trim().toLowerCase();
  if (p == 'paid') return 'paid';
  if (p == 'draft') return 'draft';
  if (p == 'due_soon') return 'due_soon';
  // `pending_delivery`: client-only filter (same full list as `due`).
  if (p == 'pending_delivery' || p == 'received' || p == 'delivery_stuck') {
    return null;
  }
  // `all`, `due`, and anything else → full list (client filters for `due`).
  return null;
}

/// Bust list + catalog-intel snapshots together.
void invalidateTradePurchaseCaches(dynamic ref) {
  ref.invalidate(tradePurchasesListProvider);
  ref.invalidate(tradePurchasesForAlertsProvider);
  ref.invalidate(tradePurchasesCatalogIntelProvider);
}

/// Same as [invalidateTradePurchaseCaches] for use after async gaps where [WidgetRef] may be disposed.
void invalidateTradePurchaseCachesFromContainer(ProviderContainer container) {
  container.invalidate(tradePurchasesListProvider);
  container.invalidate(tradePurchasesForAlertsProvider);
  container.invalidate(tradePurchasesCatalogIntelProvider);
}

/// Primary history chip / route filter (client state). Use [_tradeListApiStatus] for API.
final purchaseHistoryPrimaryFilterProvider =
    StateProvider<String>((ref) => 'all');

/// Client-side filter only (not sent to list API — avoids refetch per keystroke).
final purchaseHistorySearchProvider = StateProvider<String>((ref) => '');

/// Optional secondary filter: `pending` | `overdue` (client-side; paid uses primary).
final purchaseHistorySecondaryFilterProvider =
    StateProvider<String?>((ref) => null);

/// Advanced filters (sheet). Substrings match supplier/broker names client-side.
final purchaseHistorySortNewestFirstProvider =
    StateProvider<bool>((ref) => true);

final purchaseHistorySupplierContainsProvider =
    StateProvider<String?>((ref) => null);

final purchaseHistoryBrokerContainsProvider =
    StateProvider<String?>((ref) => null);

/// `bag` | `box` | `tin` | `mixed` — client-side only.
final purchaseHistoryPackKindFilterProvider =
    StateProvider<String?>((ref) => null);

final purchaseHistoryDateFromProvider =
    StateProvider<DateTime?>((ref) => null);

final purchaseHistoryDateToProvider =
    StateProvider<DateTime?>((ref) => null);

/// Unfiltered list for due/overdue alert derivation (ignores history tab filters).
final tradePurchasesForAlertsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final link = ref.keepAlive();
  final t = Timer(const Duration(minutes: 8), link.close);
  ref.onDispose(t.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
        limit: kTradePurchasesAlertFetchLimit,
      );
});

final tradePurchasesForAlertsParsedProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  return ref.watch(tradePurchasesForAlertsProvider).whenData(
        (maps) => maps
            .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
});

/// Paged trade rows for Purchase History (offset grows via [TradePurchasesListNotifier.loadMore]).
class TradePurchasesListView {
  const TradePurchasesListView({required this.rows, required this.hasMore});

  final List<Map<String, dynamic>> rows;
  final bool hasMore;
}

class TradePurchasesListNotifier extends AutoDisposeAsyncNotifier<TradePurchasesListView> {
  bool _loadMoreBusy = false;

  @override
  Future<TradePurchasesListView> build() async {
    final link = ref.keepAlive();
    final t = Timer(const Duration(minutes: 8), link.close);
    ref.onDispose(t.cancel);

    final session = ref.watch(sessionProvider);
    if (session == null) {
      return const TradePurchasesListView(rows: [], hasMore: false);
    }
    final branch = ref.watch(shellCurrentBranchProvider);
    if (branch != ShellBranch.history) {
      // IndexedStack mounts History off-screen; defer list API until tab visible.
      return const TradePurchasesListView(rows: [], hasMore: false);
    }
    final primary = ref.watch(purchaseHistoryPrimaryFilterProvider);
    final secondary = ref.watch(purchaseHistorySecondaryFilterProvider);
    final apiStatus = _tradeListApiStatus(primary, secondary);
    final purchaseFrom = _purchaseFromApi(ref.watch(purchaseHistoryDateFromProvider));
    final purchaseTo = _purchaseFromApi(ref.watch(purchaseHistoryDateToProvider));

    final page = await ref.read(hexaApiProvider).listTradePurchases(
          businessId: session.primaryBusiness.id,
          limit: kTradePurchasesHistoryFetchLimit,
          offset: 0,
          status: apiStatus,
          purchaseFrom: purchaseFrom,
          purchaseTo: purchaseTo,
        );
    final hasMore = page.length >= kTradePurchasesHistoryFetchLimit;
    return TradePurchasesListView(rows: page, hasMore: hasMore);
  }

  /// Appends the next API page when the user scrolls near the end of the list.
  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (cur == null || !cur.hasMore || _loadMoreBusy) return;
    if (ref.read(shellCurrentBranchProvider) != ShellBranch.history) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final offset = cur.rows.length;
    _loadMoreBusy = true;
    try {
      final primary = ref.read(purchaseHistoryPrimaryFilterProvider);
      final secondary = ref.read(purchaseHistorySecondaryFilterProvider);
      final apiStatus = _tradeListApiStatus(primary, secondary);
      final purchaseFrom = _purchaseFromApi(ref.read(purchaseHistoryDateFromProvider));
      final purchaseTo = _purchaseFromApi(ref.read(purchaseHistoryDateToProvider));
      final page = await ref.read(hexaApiProvider).listTradePurchases(
            businessId: session.primaryBusiness.id,
            limit: kTradePurchasesHistoryFetchLimit,
            offset: offset,
            status: apiStatus,
            purchaseFrom: purchaseFrom,
            purchaseTo: purchaseTo,
          );
      final after = state.valueOrNull;
      if (after == null || after.rows.length != offset) return;
      if (page.isEmpty) {
        state = AsyncData(TradePurchasesListView(rows: after.rows, hasMore: false));
        return;
      }
      final hasMore = page.length >= kTradePurchasesHistoryFetchLimit;
      state = AsyncData(TradePurchasesListView(
        rows: [...after.rows, ...page],
        hasMore: hasMore,
      ));
    } finally {
      _loadMoreBusy = false;
    }
  }
}

final tradePurchasesListProvider =
    AsyncNotifierProvider.autoDispose<TradePurchasesListNotifier, TradePurchasesListView>(
  TradePurchasesListNotifier.new,
);

/// Parsed rows track [tradePurchasesListProvider] without `await …future`, so
/// async completion cannot call `markNeedsBuild` on a disposed home/shell
/// element after a fast navigation or 401-driven route swap (Riverpod #…).
final tradePurchasesParsedProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  return ref.watch(tradePurchasesListProvider).whenData(
        (view) => view.rows
            .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
});

/// Counts for dashboard / history banner.
final purchaseAlertsProvider = Provider.autoDispose<Map<String, int>>((ref) {
  final async = ref.watch(tradePurchasesParsedProvider);
  return async.maybeWhen(
    data: (list) {
      var dueSoon = 0;
      var overdue = 0;
      var paid = 0;
      var dueToday = 0;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      for (final p in list) {
        final st = p.statusEnum;
        if (st == PurchaseStatus.dueSoon) dueSoon++;
        if (st == PurchaseStatus.overdue) overdue++;
        if (st == PurchaseStatus.paid) paid++;
        if (p.dueDate != null) {
          final d = DateTime(p.dueDate!.year, p.dueDate!.month, p.dueDate!.day);
          if (d == today &&
              st != PurchaseStatus.paid &&
              st != PurchaseStatus.cancelled) {
            dueToday++;
          }
        }
      }
      return {
        'dueSoon': dueSoon,
        'overdue': overdue,
        'paid': paid,
        'dueToday': dueToday,
      };
    },
    orElse: () =>
        {'dueSoon': 0, 'overdue': 0, 'paid': 0, 'dueToday': 0},
  );
});

/// Period strip for Purchase History: aligns with [analyticsDateRangeProvider]
/// (same period as Reports/Home Month preset).
final purchaseHistoryMonthStatsProvider =
    Provider.autoDispose<PurchaseHistoryMonthStats>((ref) {
  final async = ref.watch(tradePurchasesForAlertsParsedProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  return async.maybeWhen(
    data: (list) => computePurchaseHistoryRangeStats(
      list,
      from: range.from,
      to: range.to,
    ),
    orElse: () => PurchaseHistoryMonthStats.empty,
  );
});

/// Bags / boxes / tins from loaded trade purchase lines.
final purchaseUnitTotalsProvider =
    Provider.autoDispose<({int bags, int boxes, int tins})>((ref) {
  final async = ref.watch(tradePurchasesParsedProvider);
  return async.maybeWhen(
    data: (list) {
      var bags = 0;
      var boxes = 0;
      var tins = 0;
      for (final p in list) {
        for (final ln in p.lines) {
          final u = ln.unit.toUpperCase();
          final q = ln.qty.round();
          if (unitCountsAsBagFamily(ln.unit)) bags += q;
          if (u.contains('BOX')) boxes += q;
          if (u.contains('TIN')) tins += q;
        }
      }
      return (bags: bags, boxes: boxes, tins: tins);
    },
    orElse: () => (bags: 0, boxes: 0, tins: 0),
  );
});

/// Trade list for catalog item intel — full list, not tied to History tab filters.
final tradePurchasesCatalogIntelProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final link = ref.keepAlive();
  final t = Timer(const Duration(minutes: 8), link.close);
  ref.onDispose(t.cancel);
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
        limit: kTradePurchasesAlertFetchLimit,
      );
});

final tradePurchasesCatalogIntelParsedProvider =
    Provider.autoDispose<AsyncValue<List<TradePurchase>>>((ref) {
  return ref.watch(tradePurchasesCatalogIntelProvider).whenData(
        (maps) => maps
            .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
});
