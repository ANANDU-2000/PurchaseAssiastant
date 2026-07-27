import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/json_coerce.dart';
import '../../../core/navigation/open_trade_item_from_report.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/widgets/focused_search_chrome.dart';
import '../home_pack_unit_word.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(1);

String _itemUpperQtyLine(Map<String, dynamic> m, {String? itemTitle}) {
  final tb = coerceToDouble(m['total_bags']);
  final txb = coerceToDouble(m['total_boxes']);
  final ttn = coerceToDouble(m['total_tins']);
  final tkg = coerceToDouble(m['total_kg']);
  final parts = <String>[];
  if (tb > 0) {
    parts.add('${_fmtQty(tb)} ${homePackUnitWord('BAG', tb)}');
  } else if (itemTitle != null && itemTitle.trim().isNotEmpty) {
    final inferred = inferBagCountForKgOnlyDisplay(
      itemName: itemTitle,
      totalKg: tkg,
      totalBags: tb,
    );
    if (inferred != null) {
      final ib = inferred.toDouble();
      parts.add('${_fmtQty(ib)} ${homePackUnitWord('BAG', ib)}');
    }
  }
  if (txb > 0) parts.add('${_fmtQty(txb)} ${homePackUnitWord('BOX', txb)}');
  if (ttn > 0) parts.add('${_fmtQty(ttn)} ${homePackUnitWord('TIN', ttn)}');
  if (tkg > 0) parts.add('${_fmtQty(tkg)} KG');
  if (parts.isNotEmpty) return parts.join(' • ');
  final q = coerceToDouble(m['total_qty']);
  return homePackQtyWithDbUnit(q, m['unit']?.toString());
}

String _categoryQtyLabel(CategoryStat c) {
  final parts = <String>[];
  if (c.units.bags > 0) {
    parts.add(
        '${_fmtQty(c.units.bags)} ${homePackUnitWord('BAG', c.units.bags)}');
  }
  if (c.units.boxes > 0) {
    parts.add(
        '${_fmtQty(c.units.boxes)} ${homePackUnitWord('BOX', c.units.boxes)}');
  }
  if (c.units.tins > 0) {
    parts.add(
        '${_fmtQty(c.units.tins)} ${homePackUnitWord('TIN', c.units.tins)}');
  }
  if (parts.isNotEmpty) return parts.join(' • ');
  if (c.items.isNotEmpty) {
    final u = c.items.first.unit.trim();
    if (u.isNotEmpty && u != '—') {
      return homePackQtyWithDbUnit(c.totalQty, u);
    }
  }
  return '${_fmtQty(c.totalQty)} QTY';
}

String _dashboardUnitsLine(HomeDashboardData d) {
  return _dashboardUnitsLineFromTotals(
    bags: d.totalBags,
    boxes: d.totalBoxes,
    tins: d.totalTins,
    kg: d.totalKg,
  );
}

String _dashboardUnitsLineFromTotals({
  required double bags,
  required double boxes,
  required double tins,
  required double kg,
}) {
  final parts = <String>[];
  if (bags > 0) {
    parts.add('${_fmtQty(bags)} ${homePackUnitWord('BAG', bags)}');
  }
  if (boxes > 0) {
    parts.add('${_fmtQty(boxes)} ${homePackUnitWord('BOX', boxes)}');
  }
  if (tins > 0) {
    parts.add('${_fmtQty(tins)} ${homePackUnitWord('TIN', tins)}');
  }
  if (kg > 0) parts.add('${_fmtQty(kg)} KG');
  if (parts.isNotEmpty) return parts.join(' • ');
  return '0 KG';
}

({double bags, double boxes, double tins, double kg})? _unitsFromShellItems(
  HomeShellReportsBundle? b,
) {
  if (b == null || b.items.isEmpty) return null;
  double bags = 0, boxes = 0, tins = 0, kg = 0;
  for (final m in b.items) {
    bags += coerceToDouble(m['total_bags']);
    boxes += coerceToDouble(m['total_boxes']);
    tins += coerceToDouble(m['total_tins']);
    kg += coerceToDouble(m['total_kg']);
  }
  if (bags.abs() < 1e-9 &&
      boxes.abs() < 1e-9 &&
      tins.abs() < 1e-9 &&
      kg.abs() < 1e-9) {
    return null;
  }
  return (bags: bags, boxes: boxes, tins: tins, kg: kg);
}

bool _breakdownRowMatchesQuery({
  required String title,
  required String qtyLine,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return title.toLowerCase().contains(q) || qtyLine.toLowerCase().contains(q);
}

class HomeBreakdownListPage extends ConsumerStatefulWidget {
  const HomeBreakdownListPage({super.key, required this.tab});
  final HomeBreakdownTab tab;

  @override
  ConsumerState<HomeBreakdownListPage> createState() =>
      _HomeBreakdownListPageState();
}

class _HomeBreakdownListPageState extends ConsumerState<HomeBreakdownListPage> {
  final _breakdownSearchCtrl = TextEditingController();
  final _breakdownSearchFocus = FocusNode();

  static const _dotColors = <Color>[
    Color(0xFF0D9488),
    Color(0xFF6366F1),
    Color(0xFFEA580C),
    Color(0xFF7C3AED),
    Color(0xFF0EA5E9),
    Color(0xFFDB2777),
    Color(0xFFCA8A04),
    Color(0xFF16A34A),
  ];

  @override
  void initState() {
    super.initState();
    _breakdownSearchCtrl.addListener(() => setState(() {}));
    _breakdownSearchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _breakdownSearchCtrl.dispose();
    _breakdownSearchFocus.dispose();
    super.dispose();
  }

  bool get _breakdownSearchActive =>
      _breakdownSearchFocus.hasFocus ||
      _breakdownSearchCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final ref = this.ref;
    final title = 'All — ${tab.label}';
    final asyncDash = ref.watch(homeDashboardDataProvider);
    final peekDash = ref.watch(homeDashboardSyncCacheProvider);
    final asyncShell = ref.watch(homeShellReportsProvider);
    final peekShell = ref.watch(homeShellReportsSyncCacheProvider);
    final pay = asyncDash.snapshot;
    final dashboard =
        pay.data.isEmpty ? (peekDash ?? pay.data) : pay.data;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        backgroundColor: HexaColors.brandBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
      ),
      body: switch (tab) {
        HomeBreakdownTab.category => () {
              if (asyncDash.refreshing &&
                  peekDash == null &&
                  pay.data.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = dashboard.categories
                  .where((e) => e.totalAmount > 0)
                  .toList()
                ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));
              return _buildScroll(
                header: _totalHeader(dashboard),
                showBreakdownSearch: false,
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _rowCategory(context, rows[i], i),
                ],
              );
            }(),
        _ => () {
              if (asyncShell.isLoading &&
                  asyncShell.valueOrNull == null &&
                  peekShell == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final bundle = asyncShell.valueOrNull ??
                  peekShell ??
                  HomeShellReportsBundle.empty;
              final unitsOverride = _unitsFromShellItems(bundle);
              return switch (tab) {
                HomeBreakdownTab.subcategory =>
                  _subList(context, bundle, dashboard, unitsOverride),
                HomeBreakdownTab.supplier =>
                  _supList(context, bundle, dashboard, unitsOverride),
                HomeBreakdownTab.items =>
                  _itemList(context, bundle, dashboard, unitsOverride),
                HomeBreakdownTab.category => const SizedBox.shrink(),
              };
            }(),
      },
    );
  }

  Widget _buildScroll({
    Widget? header,
    required List<Widget> children,
    bool showBreakdownSearch = false,
  }) {
    final searchField = TextField(
      controller: _breakdownSearchCtrl,
      focusNode: _breakdownSearchFocus,
      decoration: InputDecoration(
        hintText: 'Search title or quantity…',
        isDense: true,
        prefixIcon: const Icon(Icons.search_rounded, size: 22),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: HexaColors.brandBorder),
        ),
        suffixIcon: _breakdownSearchCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _breakdownSearchCtrl.clear();
                  setState(() {});
                },
              ),
      ),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (showBreakdownSearch) ...[
          searchField,
          const SizedBox(height: 10),
        ],
        if (header != null) ...[
          CollapsibleSearchChrome(
            searchActive: showBreakdownSearch && _breakdownSearchActive,
            chrome: header,
          ),
          const SizedBox(height: 10),
        ],
        ...children,
      ],
    );
  }

  Widget _totalHeader(
    HomeDashboardData d, [
    ({double bags, double boxes, double tins, double kg})? unitsOverride,
  ]) {
    final unitsLine = unitsOverride == null
        ? _dashboardUnitsLine(d)
        : _dashboardUnitsLineFromTotals(
            bags: unitsOverride.bags,
            boxes: unitsOverride.boxes,
            tins: unitsOverride.tins,
            kg: unitsOverride.kg,
          );
    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: HexaColors.brandBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            const Text(
              'Total:',
              style: TextStyle(
                fontSize: 12,
                color: HexaColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _inr(d.totalPurchase),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                unitsLine,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rowCategory(
    BuildContext context,
    CategoryStat row,
    int index,
  ) {
    final sup = (row.subtitleSupplier?.trim().isNotEmpty == true)
        ? row.subtitleSupplier!
        : '—';
    final bro = (row.subtitleBroker?.trim().isNotEmpty == true)
        ? row.subtitleBroker!
        : '—';
    final dot = _dotColors[index % _dotColors.length];
    return _breakdownTile(
      dot: dot,
      title: row.categoryName,
      amount: row.totalAmount,
      boldLine2: _categoryQtyLabel(row),
      rest1: sup,
      rest2: bro,
      onTap: () {
        if (row.categoryId == '_uncat') {
          context.go('/catalog');
        } else {
          context.go('/catalog/category/${row.categoryId}');
        }
      },
    );
  }

  Widget _subList(
    BuildContext context,
    HomeShellReportsBundle b,
    HomeDashboardData? dashboard,
    ({double bags, double boxes, double tins, double kg})? unitsOverride,
  ) {
    final rows = List<Map<String, dynamic>>.from(b.subcategories)
      ..sort((a, c) {
        final pa = coerceToDouble(a['total_purchase']);
        final pc = coerceToDouble(c['total_purchase']);
        return pc.compareTo(pa);
      });
    final q = _breakdownSearchCtrl.text;
    final filtered = rows.where((a) {
      final typ = a['type_name']?.toString().trim() ?? '';
      final title = typ.isNotEmpty
          ? typ
          : (a['category_name']?.toString() ?? '—');
      return _breakdownRowMatchesQuery(
        title: title,
        qtyLine: _itemUpperQtyLine(a),
        query: q,
      );
    }).toList();
    return _buildScroll(
      header: dashboard == null ? null : _totalHeader(dashboard, unitsOverride),
      showBreakdownSearch: true,
      children: [
        for (var i = 0; i < filtered.length; i++)
          _rowSub(context, filtered[i], i),
      ],
    );
  }

  Widget _rowSub(BuildContext context, Map<String, dynamic> r, int index) {
    final typ = r['type_name']?.toString().trim() ?? '';
    final title = typ.isNotEmpty
        ? typ
        : (r['category_name']?.toString() ?? '—');
    final amt = coerceToDouble(r['total_purchase']);
    final dot = _dotColors[index % _dotColors.length];
    return _breakdownTile(
      dot: dot,
      title: title,
      amount: amt,
      boldLine2: _itemUpperQtyLine(r),
      onTap: () {
        final tid =
            (r['type_id'] ?? r['typeId'])?.toString().trim() ?? '';
        final cid =
            (r['category_id'] ?? r['categoryId'])?.toString().trim() ?? '';
        if (tid.isNotEmpty && cid.isNotEmpty) {
          context.push('/catalog/category/$cid/type/$tid');
        } else if (cid.isNotEmpty) {
          context.push('/catalog/category/$cid');
        } else {
          context.go('/catalog');
        }
      },
    );
  }

  Widget _supList(
    BuildContext context,
    HomeShellReportsBundle b,
    HomeDashboardData? dashboard,
    ({double bags, double boxes, double tins, double kg})? unitsOverride,
  ) {
    final rows = List<Map<String, dynamic>>.from(b.suppliers)
      ..sort((a, c) {
        final pa = coerceToDouble(a['total_purchase']);
        final pc = coerceToDouble(c['total_purchase']);
        return pc.compareTo(pa);
      });
    final q = _breakdownSearchCtrl.text;
    final filtered = rows.where((a) {
      final name = a['supplier_name']?.toString() ?? '—';
      return _breakdownRowMatchesQuery(
        title: name,
        qtyLine: _itemUpperQtyLine(a),
        query: q,
      );
    }).toList();
    return _buildScroll(
      header: dashboard == null ? null : _totalHeader(dashboard, unitsOverride),
      showBreakdownSearch: true,
      children: [
        for (var i = 0; i < filtered.length; i++)
          _rowSup(context, filtered[i], i),
      ],
    );
  }

  Widget _rowSup(BuildContext context, Map<String, dynamic> r, int index) {
    final name = r['supplier_name']?.toString() ?? '—';
    final amt = coerceToDouble(r['total_purchase']);
    final sid = r['supplier_id']?.toString() ?? '';
    final dot = _dotColors[index % _dotColors.length];
    return _breakdownTile(
      dot: dot,
      title: name,
      amount: amt,
      boldLine2: _itemUpperQtyLine(r),
      onTap: () {
        if (sid.isNotEmpty) {
          context.push('/supplier/$sid');
        }
      },
    );
  }

  Widget _itemList(
    BuildContext context,
    HomeShellReportsBundle b,
    HomeDashboardData? dashboard,
    ({double bags, double boxes, double tins, double kg})? unitsOverride,
  ) {
    final rows = List<Map<String, dynamic>>.from(b.items)
      ..sort((a, c) {
        final pa = coerceToDouble(a['total_purchase']);
        final pc = coerceToDouble(c['total_purchase']);
        return pc.compareTo(pa);
      });
    final q = _breakdownSearchCtrl.text;
    final filtered = rows.where((a) {
      final name = a['item_name']?.toString() ?? '—';
      return _breakdownRowMatchesQuery(
        title: name,
        qtyLine: _itemUpperQtyLine(a, itemTitle: name),
        query: q,
      );
    }).toList();
    return _buildScroll(
      header: dashboard == null ? null : _totalHeader(dashboard, unitsOverride),
      showBreakdownSearch: true,
      children: [
        for (var i = 0; i < filtered.length; i++)
          _rowItem(context, filtered[i], i),
      ],
    );
  }

  Widget _rowItem(BuildContext context, Map<String, dynamic> r, int index) {
    final name = r['item_name']?.toString() ?? '—';
    final amt = coerceToDouble(r['total_purchase']);
    final bold = _itemUpperQtyLine(r, itemTitle: name);
    final dot = _dotColors[index % _dotColors.length];
    return _breakdownTile(
      dot: dot,
      title: name,
      amount: amt,
      boldLine2: bold,
      onTap: () {
        unawaited(openTradeItemFromReportRow(context, ref, r));
      },
    );
  }

  Widget _breakdownTile({
    required Color dot,
    required String title,
    required double amount,
    required String boldLine2,
    String? rest1,
    String? rest2,
    required VoidCallback onTap,
  }) {
    final tail = <String>[
      if (rest1 != null && rest1.trim().isNotEmpty && rest1.trim() != '—') rest1.trim(),
      if (rest2 != null && rest2.trim().isNotEmpty && rest2.trim() != '—') rest2.trim(),
    ].join(' · ');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dot,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Text(
                    _inr(amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 12, height: 1.2),
                    children: [
                      TextSpan(
                        text: boldLine2,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (tail.isNotEmpty)
                        TextSpan(
                          text: ' · $tail',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF64748B),
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
