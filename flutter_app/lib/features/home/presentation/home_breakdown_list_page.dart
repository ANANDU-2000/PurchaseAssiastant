import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/home_breakdown_tab_providers.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../home_pack_unit_word.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(1);

String _itemUpperQtyLine(Map<String, dynamic> m) {
  final tb = (m['total_bags'] as num?)?.toDouble() ?? 0;
  final txb = (m['total_boxes'] as num?)?.toDouble() ?? 0;
  final ttn = (m['total_tins'] as num?)?.toDouble() ?? 0;
  final tkg = (m['total_kg'] as num?)?.toDouble() ?? 0;
  final parts = <String>[];
  if (tb > 0) parts.add('${_fmtQty(tb)} ${homePackUnitWord('BAG', tb)}');
  if (txb > 0) parts.add('${_fmtQty(txb)} ${homePackUnitWord('BOX', txb)}');
  if (ttn > 0) parts.add('${_fmtQty(ttn)} ${homePackUnitWord('TIN', ttn)}');
  if (tkg > 0) parts.add('${_fmtQty(tkg)} KG');
  if (parts.isNotEmpty) return parts.join(' • ');
  final q = (m['total_qty'] as num?)?.toDouble() ?? 0;
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
  final parts = <String>[];
  if (d.totalBags > 0) {
    parts.add(
        '${_fmtQty(d.totalBags)} ${homePackUnitWord('BAG', d.totalBags)}');
  }
  if (d.totalBoxes > 0) {
    parts.add(
        '${_fmtQty(d.totalBoxes)} ${homePackUnitWord('BOX', d.totalBoxes)}');
  }
  if (d.totalTins > 0) {
    parts.add(
        '${_fmtQty(d.totalTins)} ${homePackUnitWord('TIN', d.totalTins)}');
  }
  if (d.totalKg > 0) parts.add('${_fmtQty(d.totalKg)} KG');
  if (parts.isNotEmpty) return parts.join(' • ');
  return '0 KG';
}

class HomeBreakdownListPage extends ConsumerWidget {
  const HomeBreakdownListPage({super.key, required this.tab});
  final HomeBreakdownTab tab;

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
  Widget build(BuildContext context, WidgetRef ref) {
    final title = 'All — ${tab.label}';
    final asyncDash = ref.watch(homeDashboardDataProvider);
    final peekDash = ref.watch(homeDashboardSyncCacheProvider);
    final asyncShell = ref.watch(homeShellReportsProvider);
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
          onPressed: () => context.pop(),
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
                children: [
                  for (var i = 0; i < rows.length; i++)
                    _rowCategory(context, rows[i], i),
                ],
              );
            }(),
        _ => () {
              if (asyncShell.isLoading && asyncShell.valueOrNull == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final bundle =
                  asyncShell.valueOrNull ?? HomeShellReportsBundle.empty;
              return switch (tab) {
                HomeBreakdownTab.subcategory =>
                  _subList(context, bundle, dashboard),
                HomeBreakdownTab.supplier =>
                  _supList(context, bundle, dashboard),
                HomeBreakdownTab.items =>
                  _itemList(context, bundle, dashboard),
                HomeBreakdownTab.category => const SizedBox.shrink(),
              };
            }(),
      },
    );
  }

  Widget _buildScroll({Widget? header, required List<Widget> children}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (header != null) ...[
          header,
          const SizedBox(height: 10),
        ],
        ...children,
      ],
    );
  }

  Widget _totalHeader(HomeDashboardData d) {
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
                _dashboardUnitsLine(d),
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
  ) {
    final rows = List<Map<String, dynamic>>.from(b.subcategories)
      ..sort((a, c) {
        final pa = (a['total_purchase'] as num?)?.toDouble() ?? 0;
        final pc = (c['total_purchase'] as num?)?.toDouble() ?? 0;
        return pc.compareTo(pa);
      });
    return _buildScroll(
      header: dashboard == null ? null : _totalHeader(dashboard),
      children: [
        for (var i = 0; i < rows.length; i++)
          _rowSub(context, rows[i], i),
      ],
    );
  }

  Widget _rowSub(BuildContext context, Map<String, dynamic> r, int index) {
    final typ = r['type_name']?.toString().trim() ?? '';
    final title = typ.isNotEmpty
        ? typ
        : (r['category_name']?.toString() ?? '—');
    final amt = (r['total_purchase'] as num?)?.toDouble() ?? 0;
    final dot = _dotColors[index % _dotColors.length];
    return _breakdownTile(
      dot: dot,
      title: title,
      amount: amt,
      boldLine2: _itemUpperQtyLine(r),
      rest1: '—',
      rest2: '—',
      onTap: () => context.go('/catalog'),
    );
  }

  Widget _supList(
    BuildContext context,
    HomeShellReportsBundle b,
    HomeDashboardData? dashboard,
  ) {
    final rows = List<Map<String, dynamic>>.from(b.suppliers)
      ..sort((a, c) {
        final pa = (a['total_purchase'] as num?)?.toDouble() ?? 0;
        final pc = (c['total_purchase'] as num?)?.toDouble() ?? 0;
        return pc.compareTo(pa);
      });
    return _buildScroll(
      header: dashboard == null ? null : _totalHeader(dashboard),
      children: [
        for (var i = 0; i < rows.length; i++)
          _rowSup(context, rows[i], i),
      ],
    );
  }

  Widget _rowSup(BuildContext context, Map<String, dynamic> r, int index) {
    final name = r['supplier_name']?.toString() ?? '—';
    final amt = (r['total_purchase'] as num?)?.toDouble() ?? 0;
    final sid = r['supplier_id']?.toString() ?? '';
    final dot = _dotColors[index % _dotColors.length];
    return _breakdownTile(
      dot: dot,
      title: name,
      amount: amt,
      boldLine2: _itemUpperQtyLine(r),
      rest1: '—',
      rest2: '—',
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
  ) {
    final rows = List<Map<String, dynamic>>.from(b.items)
      ..sort((a, c) {
        final pa = (a['total_purchase'] as num?)?.toDouble() ?? 0;
        final pc = (c['total_purchase'] as num?)?.toDouble() ?? 0;
        return pc.compareTo(pa);
      });
    return _buildScroll(
      header: dashboard == null ? null : _totalHeader(dashboard),
      children: [
        for (var i = 0; i < rows.length; i++)
          _rowItem(context, rows[i], i),
      ],
    );
  }

  Widget _rowItem(BuildContext context, Map<String, dynamic> r, int index) {
    final name = r['item_name']?.toString() ?? '—';
    final amt = (r['total_purchase'] as num?)?.toDouble() ?? 0;
    final bold = _itemUpperQtyLine(r);
    final dot = _dotColors[index % _dotColors.length];
    return _breakdownTile(
      dot: dot,
      title: name,
      amount: amt,
      boldLine2: bold,
      rest1: '—',
      rest2: '—',
      onTap: () {
        final enc = Uri.encodeComponent(name);
        context.push('/item-analytics/$enc');
      },
    );
  }

  Widget _breakdownTile({
    required Color dot,
    required String title,
    required double amount,
    required String boldLine2,
    required String rest1,
    required String rest2,
    required VoidCallback onTap,
  }) {
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
                      TextSpan(
                        text: ' · $rest1 · $rest2',
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
