import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/utils/unit_utils.dart';

String reportsItemInr0(num n) => NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);

String reportsItemFmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return '—';
  return DateFormat('d MMM yyyy').format(d.toLocal());
}

String reportsPeriodQtyLine(Map<String, dynamic> summary, Map<String, dynamic> item) {
  final kg = (summary['total_weight_kg'] as num?)?.toDouble() ?? 0;
  final qty = (summary['total_qty'] as num?)?.toDouble() ?? 0;
  final unit = (item['stock_unit'] as String? ?? '').trim().toLowerCase();
  final parts = <String>[];
  if (kg > 0.001) {
    parts.add('${formatStockQtyForUnit('kg', kg)} KG');
  }
  if (qty > 0.001) {
    final u = unit.isEmpty ? 'unit' : unit;
    parts.add('${formatStockQtyForUnit(u, qty)} ${u.toUpperCase()}');
  }
  return parts.join(' • ');
}

class ReportsItemSnapshotCard extends StatelessWidget {
  const ReportsItemSnapshotCard({super.key, required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final category = (item['category'] as String? ?? '').trim();
    final sub = (item['subcategory'] as String? ?? '').trim();
    final code = (item['item_code'] as String? ?? '').trim();
    final barcode = (item['barcode'] as String? ?? '').trim();
    final unit = (item['stock_unit'] as String? ?? '').trim();
    final sys = (item['current_stock'] as num?)?.toDouble() ?? 0;
    final phys = item['physical_stock_qty'] as num?;
    final reorder = (item['reorder_level'] as num?)?.toDouble() ?? 0;
    final rack = (item['rack_location'] as String? ?? '').trim();
    final lastBy = (item['last_stock_updated_by'] as String? ?? '').trim();
    final lastAt = reportsItemFmtDate(item['last_stock_updated_at'] as String?);
    final lastSup = (item['last_supplier_name'] as String? ?? '').trim();

    String stockLine() {
      final u = unit.isEmpty ? '' : ' $unit';
      final sysS = '${formatStockQtyForUnit(unit.isEmpty ? 'unit' : unit, sys)}$u (system)';
      if (phys == null) return sysS;
      return '$sysS · ${formatStockQtyForUnit(unit.isEmpty ? 'unit' : unit, phys.toDouble())}$u (physical)';
    }

    final chips = <String>[
      if (category.isNotEmpty) category,
      if (sub.isNotEmpty) sub,
      if (code.isNotEmpty) 'Code $code',
      if (barcode.isNotEmpty) 'Barcode $barcode',
      if (rack.isNotEmpty) 'Rack $rack',
      if (reorder > 0) 'Reorder ${formatStockQtyForUnit(unit.isEmpty ? 'unit' : unit, reorder)}',
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(HexaOp.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Item details', style: HexaOp.cardTitle(context)),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: chips
                    .map(
                      (c) => Chip(
                        label: Text(c, style: const TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 10),
            Text(stockLine(), style: const TextStyle(fontWeight: FontWeight.w700)),
            if (lastBy.isNotEmpty || lastAt != '—')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Stock updated${lastBy.isNotEmpty ? ' by $lastBy' : ''}${lastAt != '—' ? ' · $lastAt' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            if (lastSup.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Last supplier: $lastSup',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ReportsItemPeriodStrip extends StatelessWidget {
  const ReportsItemPeriodStrip({
    super.key,
    required this.summary,
    required this.item,
  });

  final Map<String, dynamic> summary;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final purchase = (summary['total_purchase'] as num?)?.toDouble() ?? 0;
    final bills = (summary['purchase_count'] as num?)?.toInt() ?? 0;
    final suppliers = (summary['supplier_count'] as num?)?.toInt() ?? 0;
    final rateMin = (summary['rate_min'] as num?)?.toDouble() ?? 0;
    final rateMax = (summary['rate_max'] as num?)?.toDouble() ?? 0;
    final qtyLine = reportsPeriodQtyLine(summary, item);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'In selected period',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: HexaColors.brandPrimary.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _PeriodCell(
                  label: 'Purchase',
                  value: reportsItemInr0(purchase.round()),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _PeriodCell(
                  label: 'Bills',
                  value: '$bills',
                  subtitle: '$suppliers suppliers',
                ),
              ),
            ],
          ),
          if (qtyLine.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(qtyLine, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
          if (rateMax > 0.001)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Rate ${reportsItemInr0(rateMin.round())} – ${reportsItemInr0(rateMax.round())}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _PeriodCell extends StatelessWidget {
  const _PeriodCell({
    required this.label,
    required this.value,
    this.subtitle,
  });

  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HexaColors.brandPrimary.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 15,
              color: HexaColors.brandPrimary,
            ),
          ),
          if (subtitle != null)
            Text(subtitle!, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class ReportsItemPurchaseLineTile extends StatelessWidget {
  const ReportsItemPurchaseLineTile({super.key, required this.line});

  final Map<String, dynamic> line;

  @override
  Widget build(BuildContext context) {
    final purchaseId = line['purchase_id'] as String? ?? '';
    final humanId = (line['human_id'] as String? ?? '').trim();
    final supplier = (line['supplier_name'] as String? ?? '').trim();
    final entered = (line['entered_by_name'] as String? ?? '').trim();
    final date = reportsItemFmtDate(line['purchase_date'] as String?);
    final qty = (line['qty'] as num?)?.toDouble() ?? 0;
    final unit = (line['unit'] as String? ?? '').trim();
    final amount = (line['line_amount'] as num?)?.toDouble() ?? 0;
    final rate = (line['rate'] as num?)?.toDouble() ?? 0;

    final title = supplier.isNotEmpty
        ? supplier
        : (humanId.isNotEmpty ? humanId : 'Purchase');
    final meta = [
      date,
      if (qty > 0) '${formatStockQtyForUnit(unit.isEmpty ? 'unit' : unit, qty)} ${unit.toUpperCase()}',
      if (entered.isNotEmpty) entered,
    ].join(' · ');

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: purchaseId.isEmpty
            ? null
            : () => context.push('/purchase/detail/$purchaseId'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    reportsItemInr0(amount.round()),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (rate > 0)
                    Text(
                      '@ ${reportsItemInr0(rate.round())}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class ReportsItemActionBar extends StatelessWidget {
  const ReportsItemActionBar({super.key, required this.catalogItemId});

  final String catalogItemId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.push(
                '/catalog/item/$catalogItemId?tab=purchases',
              ),
              child: const Text('Catalog'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () => context.push('/stock/intelligence/$catalogItemId'),
              child: const Text('Stock'),
            ),
          ),
        ],
      ),
    );
  }
}
