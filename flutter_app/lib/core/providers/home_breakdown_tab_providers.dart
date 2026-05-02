import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';

import '../auth/session_notifier.dart';
import '../services/offline_store.dart';
import 'home_dashboard_provider.dart';

/// Breakdown view on Home (drives the ring + rows for non-category tabs).
enum HomeBreakdownTab {
  category,
  subcategory,
  supplier,
  items,
}

extension HomeBreakdownTabX on HomeBreakdownTab {
  String get label => switch (this) {
        HomeBreakdownTab.category => 'Category',
        HomeBreakdownTab.subcategory => 'Subcategory',
        HomeBreakdownTab.supplier => 'Supplier',
        HomeBreakdownTab.items => 'Items',
      };
}

/// Selected breakdown tab (Category | Subcategory | Supplier | Items).
final homeBreakdownTabProvider =
    StateProvider<HomeBreakdownTab>((ref) => HomeBreakdownTab.category);

/// `from` / `to` query strings (inclusive `to` day) for Home period — same window as
/// [homeDashboardDataProvider].
({String from, String to}) homeDateRangeForRef(Ref ref) {
  final period = ref.watch(homePeriodProvider);
  final custom = ref.watch(homeCustomDateRangeProvider);
  final range = homePeriodRange(period, now: DateTime.now(), custom: custom);
  final lastInclusive = range.end.subtract(const Duration(milliseconds: 1));
  return (
    from: _apiDate(range.start),
    to: _apiDate(lastInclusive),
  );
}

String _apiDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Per-tab trade report rows for Home (fetched in parallel; category tab uses snapshot only).
class HomeShellReportsBundle {
  const HomeShellReportsBundle({
    required this.subcategories,
    required this.suppliers,
    required this.items,
  });

  final List<Map<String, dynamic>> subcategories;
  final List<Map<String, dynamic>> suppliers;
  final List<Map<String, dynamic>> items;

  static const empty = HomeShellReportsBundle(
    subcategories: [],
    suppliers: [],
    items: [],
  );
}

HomeShellReportsBundle _homeShellFromHive(Map<String, dynamic>? raw) {
  if (raw == null) return HomeShellReportsBundle.empty;
  List<Map<String, dynamic>> lm(String key) {
    final v = raw[key];
    if (v is! List) return [];
    return v
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  return HomeShellReportsBundle(
    subcategories: lm('subcategories'),
    suppliers: lm('suppliers'),
    items: lm('items'),
  );
}

final Map<String, Future<HomeShellReportsBundle>> _shellInflight = {};

const _shellEachTimeout = Duration(seconds: 28);

Future<List<Map<String, dynamic>>> _fetchShellList(
  Future<List<Map<String, dynamic>>> Function() fn,
) async {
  try {
    return await fn().timeout(_shellEachTimeout);
  } on TimeoutException {
    return [];
  } catch (_) {
    return [];
  }
}

/// Types + suppliers + items for the current Home date range.
final homeShellReportsProvider =
    FutureProvider.autoDispose<HomeShellReportsBundle>((ref) async {
  ref.keepAlive();
  final session = ref.watch(sessionProvider);
  if (session == null) {
    return HomeShellReportsBundle.empty;
  }
  final q = homeDateRangeForRef(ref);
  final api = ref.read(hexaApiProvider);
  final bid = session.primaryBusiness.id;
  final dedupeKey = '$bid|${q.from}|${q.to}';

  Future<HomeShellReportsBundle> work() async {
    final cachedRaw =
        OfflineStore.getCachedHomeShellReports(bid, q.from, q.to);
    final reachability = await Connectivity().checkConnectivity();
    final looksOffline = reachability.isEmpty ||
        reachability.every((c) => c == ConnectivityResult.none);
    if (looksOffline) {
      return _homeShellFromHive(cachedRaw);
    }
    try {
      // Per-endpoint timeout + isolation: one slow/hung API does not block others.
      final typesF = _fetchShellList(
        () => api.tradeReportTypes(
            businessId: bid, from: q.from, to: q.to),
      );
      final supF = _fetchShellList(
        () => api.tradeReportSuppliers(
            businessId: bid, from: q.from, to: q.to),
      );
      final itemsF = _fetchShellList(
        () => api.tradeReportItems(
            businessId: bid, from: q.from, to: q.to),
      );
      final out = await Future.wait([typesF, supF, itemsF])
          .timeout(const Duration(seconds: 32));
      final bundle = HomeShellReportsBundle(
        subcategories: out[0],
        suppliers: out[1],
        items: out[2],
      );
      if (bundle.subcategories.isNotEmpty ||
          bundle.suppliers.isNotEmpty ||
          bundle.items.isNotEmpty) {
        await OfflineStore.cacheHomeShellReports(
          bid,
          q.from,
          q.to,
          subcategories: bundle.subcategories,
          suppliers: bundle.suppliers,
          items: bundle.items,
        );
      }
      return bundle;
    } on TimeoutException {
      return _homeShellFromHive(cachedRaw);
    } on DioException {
      return _homeShellFromHive(cachedRaw);
    } catch (_) {
      return _homeShellFromHive(cachedRaw);
    }
  }

  return _shellInflight.putIfAbsent(
    dedupeKey,
    () => work().whenComplete(() => _shellInflight.remove(dedupeKey)),
  );
});

HomeBreakdownTab? homeBreakdownTabFromQuery(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final t in HomeBreakdownTab.values) {
    if (t.name == raw) return t;
  }
  return null;
}
