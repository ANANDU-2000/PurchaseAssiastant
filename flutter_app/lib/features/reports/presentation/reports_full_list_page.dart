import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/line_display.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _qtyReadable(double q) =>
    q == q.roundToDouble() ? '${q.round()}' : q.toStringAsFixed(1);

String _kgReadable(double kg) {
  if (kg < 1e-9) return '0';
  if ((kg - kg.roundToDouble()).abs() < 1e-6) return '${kg.round()}';
  return kg.toStringAsFixed(1);
}

enum ReportsFullListKind { itemsBag, itemsBox, itemsTin, suppliers, brokers }

class ReportsFullListPage extends StatelessWidget {
  const ReportsFullListPage({
    super.key,
    required this.kind,
    required this.searchQuery,
    required this.agg,
  });

  final ReportsFullListKind kind;
  final String searchQuery;
  final TradeReportAgg agg;

  List<TradeReportItemRow> _filterItems(List<TradeReportItemRow> raw) {
    final t = searchQuery.trim().toLowerCase();
    if (t.isEmpty) return raw;
    return raw.where((r) => r.name.toLowerCase().contains(t)).toList();
  }

  List<TradeReportSupplierRow> _filterSup(List<TradeReportSupplierRow> raw) {
    final t = searchQuery.trim().toLowerCase();
    if (t.isEmpty) return raw;
    return raw.where((r) => r.name.toLowerCase().contains(t)).toList();
  }

  List<TradeReportBrokerRow> _filterBro(List<TradeReportBrokerRow> raw) {
    final t = searchQuery.trim().toLowerCase();
    if (t.isEmpty) return raw;
    return raw.where((r) => r.name.toLowerCase().contains(t)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final totals = agg.totals;
    final title = switch (kind) {
      ReportsFullListKind.itemsBag => 'All items · Bag',
      ReportsFullListKind.itemsBox => 'All items · Box',
      ReportsFullListKind.itemsTin => 'All items · Tin',
      ReportsFullListKind.suppliers => 'All suppliers',
      ReportsFullListKind.brokers => 'All brokers',
    };

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: HexaColors.brandCard,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Totals · ${_inr0(totals.inr)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    children: [
                      Text('Deals ${totals.deals}'),
                      Text('Bags ${_qtyReadable(totals.bags)}'),
                      Text('Kg ${_kgReadable(totals.kg)}'),
                      Text('Box ${_qtyReadable(totals.boxes)}'),
                      Text('Tin ${_qtyReadable(totals.tins)}'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: switch (kind) {
              // [Bug 7/8 fix] BAG rows: "5000 KG • 100 BAGS"; BOX/TIN: count
              // only — no kg suffix. Using shared formatPackagedQty so the
              // same rules apply across home / detail / reports / history.
              ReportsFullListKind.itemsBag => ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount:
                      _filterItems(agg.itemsBag).length,
                  itemBuilder: (c, i) {
                    final r = _filterItems(agg.itemsBag)[i];
                    final qty = formatPackagedQty(
                      unit: 'bag',
                      pieces: r.bags,
                      kg: r.kg,
                    );
                    return ListTile(
                      title: Text(r.name),
                      subtitle: Text(
                        '$qty · ${_inr0(r.amountInr)} · ${r.dealIds.length} deals',
                      ),
                    );
                  },
                ),
              ReportsFullListKind.itemsBox => ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount:
                      _filterItems(agg.itemsBox).length,
                  itemBuilder: (c, i) {
                    final r = _filterItems(agg.itemsBox)[i];
                    final qty =
                        formatPackagedQty(unit: 'box', pieces: r.boxes);
                    return ListTile(
                      title: Text(r.name),
                      subtitle: Text(
                        '$qty · ${_inr0(r.amountInr)} · ${r.dealIds.length} deals',
                      ),
                    );
                  },
                ),
              ReportsFullListKind.itemsTin => ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount:
                      _filterItems(agg.itemsTin).length,
                  itemBuilder: (c, i) {
                    final r = _filterItems(agg.itemsTin)[i];
                    final qty =
                        formatPackagedQty(unit: 'tin', pieces: r.tins);
                    return ListTile(
                      title: Text(r.name),
                      subtitle: Text(
                        '$qty · ${_inr0(r.amountInr)} · ${r.dealIds.length} deals',
                      ),
                    );
                  },
                ),
              ReportsFullListKind.suppliers => ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount:
                      _filterSup(agg.suppliers).length,
                  itemBuilder: (c, i) {
                    final s = _filterSup(agg.suppliers)[i];
                    return ListTile(
                      title: Text(s.name),
                      subtitle: Text(
                        '${s.dealIds.length} deals · bags ${_qtyReadable(s.bagQty)} · ${_kgReadable(s.bagKg)} kg',
                      ),
                    );
                  },
                ),
              ReportsFullListKind.brokers => ListView.builder(
                  padding:
                      const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount:
                      _filterBro(agg.brokers).length,
                  itemBuilder: (c, i) {
                    final b = _filterBro(agg.brokers)[i];
                    return ListTile(
                      title: Text(b.name),
                      subtitle: Text(
                        '${b.purchaseIds.length} deals · ${_inr0(b.commission)} commission',
                      ),
                    );
                  },
                ),
            },
          ),
        ],
      ),
    );
  }
}
