import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

double? tradeIntelToDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String tradeIntelFormatInr(num? n, {int decimalDigits = 0}) {
  if (n == null) return '—';
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: decimalDigits,
  ).format(n);
}

String tradeIntelFormatQty(num? n) {
  if (n == null) return '';
  if (n == n.roundToDouble()) return n.round().toString();
  return n.toStringAsFixed(2);
}

/// "5000 KG • 100 BAGS" style line from unified-search / catalog item maps.
String tradeIntelQtySummaryLine(Map<String, dynamic> m) {
  final kg = tradeIntelToDouble(m['last_line_weight_kg']);
  final qty = tradeIntelToDouble(m['last_line_qty']);
  final unit = (m['last_line_unit'] ?? '').toString().toLowerCase().trim();
  final parts = <String>[];
  if (kg != null && kg > 1e-6) {
    parts.add('${tradeIntelFormatQty(kg)} KG');
  }
  if (qty != null && qty > 1e-6) {
    if (unit == 'tin') {
      parts.add('${tradeIntelFormatQty(qty)} TIN');
    } else if (unit == 'bag' || unit == 'sack' || unit == 'box') {
      parts.add('${tradeIntelFormatQty(qty)} ${unit.toUpperCase()}');
    } else if (unit.isNotEmpty && (kg == null || kg <= 1e-6)) {
      parts.add('${tradeIntelFormatQty(qty)} ${unit.toUpperCase()}');
    }
  }
  return parts.isEmpty ? '' : parts.join(' • ');
}

/// Volume from category trade-summary rows (`period_weight_kg`, `period_qty_bags`).
String tradeIntelPeriodVolumeLine(Map<String, dynamic> m) {
  final kg = tradeIntelToDouble(m['period_weight_kg']);
  final bags = tradeIntelToDouble(m['period_qty_bags']);
  final parts = <String>[];
  if (kg != null && kg > 1e-6) {
    parts.add('${tradeIntelFormatQty(kg)} KG');
  }
  if (bags != null && bags > 1e-6) {
    parts.add('${tradeIntelFormatQty(bags)} BAGS');
  }
  if (parts.isEmpty) return '';
  return 'Volume: ${parts.join(' • ')}';
}

/// Period line amount (confirmed trade) for category rows.
String tradeIntelPeriodAmountLine(Map<String, dynamic> m) {
  final a = tradeIntelToDouble(m['period_line_total']);
  if (a == null || a <= 1e-6) return '';
  return 'Spend: ${tradeIntelFormatInr(a)}';
}

/// Last purchase → last selling (search item: last_purchase_price + last_selling_rate or default_selling_cost).
String tradeIntelRatePairLine(Map<String, dynamic> m) {
  final buy = tradeIntelToDouble(m['last_purchase_price']);
  final sell = tradeIntelToDouble(m['last_selling_rate']) ??
      tradeIntelToDouble(m['default_selling_cost']);
  if ((buy == null || buy <= 0) && (sell == null || sell <= 0)) {
    return '';
  }
  final b = buy != null && buy > 0 ? tradeIntelFormatInr(buy) : '—';
  final s = sell != null && sell > 0 ? tradeIntelFormatInr(sell) : '—';
  return 'Last: $b → $s';
}

String tradeIntelSourceLine(Map<String, dynamic> m) {
  final sup = (m['last_supplier_name'] ?? '').toString().trim();
  final bro = (m['last_broker_name'] ?? '').toString().trim();
  if (sup.isEmpty && bro.isEmpty) return '';
  if (sup.isNotEmpty && bro.isNotEmpty) return 'From: $sup · $bro';
  if (sup.isNotEmpty) return 'From: $sup';
  return 'Broker: $bro';
}

Map<String, dynamic> tradeIntelMapFromCategorySummaryItem(Map<String, dynamic> row) {
  return {
    'last_purchase_price': row['last_purchase_price'],
    'last_selling_rate': row['last_selling_rate'],
    'last_supplier_name': row['last_supplier_name'],
    'last_broker_name': row['last_broker_name'],
  };
}

/// One catalog item row from [categoryTradeSummary] `items` list.
class TradeIntelCategoryItemTile extends StatelessWidget {
  const TradeIntelCategoryItemTile({
    super.key,
    required this.row,
    required this.onTap,
    this.showChevron = true,
  });

  final Map<String, dynamic> row;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = (row['name'] ?? 'Item').toString();
    final vol = tradeIntelPeriodVolumeLine(row);
    final spend = tradeIntelPeriodAmountLine(row);
    final rate = tradeIntelRatePairLine(tradeIntelMapFromCategorySummaryItem(row));
    final src = tradeIntelSourceLine(tradeIntelMapFromCategorySummaryItem(row));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.inventory_2_outlined, color: cs.primary, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (spend.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      spend,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                  if (vol.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      vol,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (rate.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      rate,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (src.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      src,
                      style: tt.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right_rounded, size: 22),
          ],
        ),
      ),
    );
  }
}

/// Compact card for global search catalog hits (2–3 lines, business-first).
class TradeIntelCatalogSearchTile extends StatelessWidget {
  const TradeIntelCatalogSearchTile({
    super.key,
    required this.item,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = (item['name'] ?? 'Item').toString();
    final qtyLine = tradeIntelQtySummaryLine(item);
    final rateLine = tradeIntelRatePairLine(item);
    final srcLine = tradeIntelSourceLine(item);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.inventory_2_outlined, color: cs.primary, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (qtyLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      qtyLine,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ],
                  if (rateLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      rateLine,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                  if (srcLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      srcLine,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
