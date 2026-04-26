import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
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
  final out = await Future.wait([
    api.tradeReportTypes(businessId: bid, from: q.from, to: q.to),
    api.tradeReportSuppliers(businessId: bid, from: q.from, to: q.to),
    api.tradeReportItems(businessId: bid, from: q.from, to: q.to),
  ]);
  return HomeShellReportsBundle(
    subcategories: out[0],
    suppliers: out[1],
    items: out[2],
  );
});

HomeBreakdownTab? homeBreakdownTabFromQuery(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  for (final t in HomeBreakdownTab.values) {
    if (t.name == raw) return t;
  }
  return null;
}
