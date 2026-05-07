import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/line_display.dart';

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

/// Qty + weight for catalog / ledger intel maps (bags · kg order via [formatLineQtyWeight]).
String tradeIntelQtySummaryLine(Map<String, dynamic> m) {
  final kg = tradeIntelToDouble(m['last_line_weight_kg']);
  final qty = tradeIntelToDouble(m['last_line_qty']);
  final unit = (m['last_line_unit'] ?? '').toString();
  final kpu = tradeIntelToDouble(m['kg_per_unit']);
  if (qty != null && qty > 1e-6 && unit.trim().isNotEmpty) {
    final uRaw = unit.trim().toLowerCase();
    final u = uRaw == 'sack' ? 'bag' : uRaw;
    if (u == 'bag') {
      // Intel gives last_line_weight_kg; fall back to qty*kpu if needed.
      final wk =
          (kg != null && kg > 1e-6) ? kg : ((kpu != null && kpu > 0) ? qty * kpu : 0.0);
      return formatPackagedQty(unit: 'bag', pieces: qty, kg: wk);
    }
    if (u == 'box') return formatPackagedQty(unit: 'box', pieces: qty);
    if (u == 'tin') return formatPackagedQty(unit: 'tin', pieces: qty);
    if (u == 'kg') return formatPackagedQty(unit: 'kg', pieces: qty);
    return formatLineQtyWeight(
      qty: qty,
      unit: unit,
      kgPerUnit: kpu,
      totalWeightKg: kg,
    );
  }
  if (kg != null && kg > 1e-6) {
    return formatPackagedQty(unit: 'kg', pieces: kg);
  }
  return '';
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
  return 'Amount: ${tradeIntelFormatInr(a)}';
}

/// Last purchase → last selling (confirmed [last_selling_rate] only — no catalog defaults).
String tradeIntelRatePairLine(Map<String, dynamic> m) {
  final buy = tradeIntelToDouble(m['last_purchase_price']);
  final sell = tradeIntelToDouble(m['last_selling_rate']);
  if ((buy == null || buy <= 0) && (sell == null || sell <= 0)) {
    return '';
  }
  final b = buy != null && buy > 0 ? tradeIntelFormatInr(buy) : '—';
  final s = sell != null && sell > 0 ? tradeIntelFormatInr(sell) : '—';
  String suf(dynamic v) {
    final q = v?.toString().trim() ?? '';
    return q.isEmpty ? '' : '/$q';
  }

  final buyQ = m['purchase_rate_dim'];
  final sellQ = m['selling_rate_dim'];
  return 'Last: $b${suf(buyQ)} → $s${suf(sellQ)}';
}

/// Last-line bags / tins / est. bags from kg ÷ kg-per-bag (compact).
String tradeIntelLastPurchaseBagsLabel(Map<String, dynamic> m) {
  final qty = tradeIntelToDouble(m['last_line_qty']);
  final unit = (m['last_line_unit'] ?? '').toString().toLowerCase().trim();
  final kg = tradeIntelToDouble(m['last_line_weight_kg']);
  if (qty != null && qty > 1e-6) {
    if (unit == 'bag' || unit == 'sack') {
      return '${tradeIntelFormatQty(qty)} bags';
    }
    if (unit == 'box') return '${tradeIntelFormatQty(qty)} box';
    if (unit == 'tin') return '${tradeIntelFormatQty(qty)} tin';
    if (unit == 'kg') return '${tradeIntelFormatQty(qty)} kg';
  }
  if (kg != null && kg > 1e-6) {
    return '${tradeIntelFormatQty(kg)} kg';
  }
  return '';
}

/// Confirmed last-purchase facts only (no catalog guide / default rates).
String tradeIntelSearchCatalogSubtitle(Map<String, dynamic> m) {
  final parts = <String>[];
  final buy = tradeIntelToDouble(m['last_purchase_price']);
  final sell = tradeIntelToDouble(m['last_selling_rate']);
  if (buy != null && buy > 0) {
    if (sell != null && sell > 0) {
      parts.add(
          'Last buy ${tradeIntelFormatInr(buy)} · Last sell ${tradeIntelFormatInr(sell)}');
    } else {
      parts.add('Last buy ${tradeIntelFormatInr(buy)}');
    }
  } else if (sell != null && sell > 0) {
    parts.add('Last sell ${tradeIntelFormatInr(sell)}');
  }
  final bags = tradeIntelLastPurchaseBagsLabel(m);
  if (bags.isNotEmpty) parts.add(bags);
  final hid = (m['last_purchase_human_id'] ?? '').toString().trim();
  if (hid.isNotEmpty) parts.add(hid);
  if (parts.isEmpty) return '';
  return parts.join(' · ');
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
    'last_trade_human_id': row['last_trade_human_id'],
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
    final billHid = (row['last_trade_human_id'] ?? '').toString().trim();

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
                  if (billHid.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Last bill $billHid',
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
    this.fuzzyNameMatch = false,
  });

  final Map<String, dynamic> item;
  final VoidCallback? onTap;
  /// When true, hide numeric last-buy/sell lines (approximate title match).
  final bool fuzzyNameMatch;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final name = (item['name'] ?? 'Item').toString();
    final factLine =
        fuzzyNameMatch ? '' : tradeIntelSearchCatalogSubtitle(item);
    final srcLine = fuzzyNameMatch ? '' : tradeIntelSourceLine(item);

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
                  if (fuzzyNameMatch) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Approximate name match — open item to verify details.',
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                  if (!fuzzyNameMatch && factLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      factLine,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
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
