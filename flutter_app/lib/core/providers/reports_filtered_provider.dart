import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/reports/filters/reports_filter_state.dart';
import '../models/trade_purchase_models.dart';
import '../reporting/trade_report_aggregate.dart';
import 'reports_provider.dart';

/// Filtered purchases + aggregate for all Reports tabs (SSOT).
class ReportsFilteredData {
  const ReportsFilteredData({
    required this.purchases,
    required this.agg,
    required this.items,
    required this.suppliers,
    required this.brokers,
  });

  final List<TradePurchase> purchases;
  final TradeReportAgg agg;
  final List<TradeReportItemRow> items;
  final List<TradeReportSupplierRow> suppliers;
  final List<TradeReportBrokerRow> brokers;
}

ReportPackKind? _unitFilterToKind(Set<ReportsUnitFilter> units) {
  if (units.contains(ReportsUnitFilter.all) || units.isEmpty) return null;
  if (units.length > 1) return null;
  final u = units.first;
  return switch (u) {
    ReportsUnitFilter.bag => ReportPackKind.bag,
    ReportsUnitFilter.box => ReportPackKind.box,
    ReportsUnitFilter.tin => ReportPackKind.tin,
    ReportsUnitFilter.kg => null,
    ReportsUnitFilter.all => null,
  };
}

TradeReportItemSort _toItemSort(ReportsSort sort) => switch (sort) {
      ReportsSort.latest => TradeReportItemSort.latest,
      ReportsSort.highestQty => TradeReportItemSort.highQty,
      ReportsSort.highestValue => TradeReportItemSort.highQty,
      ReportsSort.az => TradeReportItemSort.latest,
    };

List<TradeReportItemRow> _sortItems(
  List<TradeReportItemRow> raw,
  ReportsSort sort,
) {
  if (sort == ReportsSort.highestValue) {
    final list = [...raw]
      ..sort((a, b) {
        final c = b.amountInr.compareTo(a.amountInr);
        if (c != 0) return c;
        return a.name.compareTo(b.name);
      });
    return list;
  }
  if (sort == ReportsSort.az) {
    final list = [...raw]..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }
  return sortTradeReportItemsAll(raw, _toItemSort(sort));
}

List<TradeReportItemRow> _filterItemsBySearch(
  List<TradeReportItemRow> rows,
  String q,
) {
  if (q.isEmpty) return rows;
  return rows.where((r) => r.name.toLowerCase().contains(q)).toList();
}

List<TradePurchase> _filterPurchases(
  List<TradePurchase> merged,
  ReportsFilterState filters,
) {
  var list = merged;
  if (filters.supplierIds.isNotEmpty) {
    list = list
        .where(
          (p) =>
              p.supplierId != null &&
              filters.supplierIds.contains(p.supplierId),
        )
        .toList();
  }
  if (filters.brokerIds.isNotEmpty) {
    list = list
        .where(
          (p) => p.brokerId != null && filters.brokerIds.contains(p.brokerId),
        )
        .toList();
  }
  return list;
}

final reportsFilteredDataProvider = Provider<ReportsFilteredData>((ref) {
  final merged = ref.watch(reportsPurchasesMergedProvider);
  final filters = ref.watch(reportsFilterProvider);
  final purchases = _filterPurchases(merged, filters);
  final kind = _unitFilterToKind(filters.units);
  final agg = buildTradeReportAgg(purchases, onlyKind: kind);

  var items = _sortItems(List.of(agg.itemsAll), filters.sort);
  final q = filters.searchQuery.trim().toLowerCase();
  items = _filterItemsBySearch(items, q);

  var suppliers = List.of(agg.suppliers);
  var brokers = List.of(agg.brokers);
  if (q.isNotEmpty) {
    suppliers =
        suppliers.where((s) => s.name.toLowerCase().contains(q)).toList();
    brokers = brokers.where((b) => b.name.toLowerCase().contains(q)).toList();
  }

  return ReportsFilteredData(
    purchases: purchases,
    agg: agg,
    items: items,
    suppliers: suppliers,
    brokers: brokers,
  );
});
