import 'package:flutter/material.dart';

import '../../core/json_coerce.dart';
import '../../core/unit_engine/stock_tracking_profile.dart';
import '../../core/utils/unit_utils.dart';

/// Unit engine + stock summary for item detail / stock intelligence.
class UnitEngineSummaryCard extends StatelessWidget {
  const UnitEngineSummaryCard({
    super.key,
    required this.item,
    this.stock,
    this.intel,
  });

  final Map<String, dynamic> item;
  final Map<String, dynamic>? stock;
  final Map<String, dynamic>? intel;

  @override
  Widget build(BuildContext context) {
    final st = stock ?? const <String, dynamic>{};
    final meta = intel ?? const <String, dynamic>{};
    final stockUnit = (meta['stock_unit'] ??
            st['stock_unit'] ??
            st['unit'] ??
            item['default_unit'] ??
            'piece')
        .toString();
    final cur = coerceToDouble(st['current_stock'] ?? meta['current_stock']);
    final kgPer = coerceToDoubleNullable(
      meta['default_kg_per_bag'] ??
          st['default_kg_per_bag'] ??
          item['default_kg_per_bag'],
    );
    final stockKg = coerceToDoubleNullable(
      meta['current_stock_kg'] ?? st['current_stock_kg'],
    );
    final dual = dualStockDisplay(
      qty: cur,
      unit: stockUnit,
      kgPerBag: kgPer,
      currentStockKg: stockKg,
    );
    final pkg = (item['package_type'] ?? st['package_type'] ?? '')
        .toString()
        .trim();
    final mode = StockTrackingMode.suggestFromName(
          item['name']?.toString() ?? '',
          categoryName: item['category_name']?.toString(),
        ) ??
        _modeFromRow(stockUnit, pkg);

    String? conversionLine;
    if (kgPer != null &&
        kgPer > 0 &&
        (stockUnit == 'bag' || stockUnit == 'piece')) {
      final u = stockUnit == 'piece' ? 'PIECE' : 'BAG';
      conversionLine = '1 $u = ${formatStockQtyNumber(kgPer)} kg';
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stock',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              dual.primary,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (dual.secondary != null) ...[
              const SizedBox(height: 2),
              Text(
                dual.secondary!,
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const Divider(height: 20),
            Text(
              'Unit engine',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            _row(context, 'Count in', _unitLabel(stockUnit)),
            if (mode != null)
              _row(
                context,
                'Packaging',
                StockTrackingMode.labelForMode(mode),
              ),
            if (conversionLine != null)
              _row(context, 'Conversion', conversionLine.toLowerCase()),
          ],
        ),
      ),
    );
  }

  static String? _modeFromRow(String unit, String pkg) {
    final p = pkg.toUpperCase();
    if (p.contains('RETAIL')) return StockTrackingMode.retailPacket;
    if (unit == 'bag') return StockTrackingMode.wholesaleBag;
    if (unit == 'kg') return StockTrackingMode.looseKg;
    if (unit == 'box') return StockTrackingMode.box;
    if (unit == 'tin') return StockTrackingMode.tin;
    return StockTrackingMode.piece;
  }

  static String _unitLabel(String unit) {
    final u = unit.trim().toLowerCase();
    if (u.isEmpty) return 'units';
    if (u == 'kg') return 'kg';
    if (u == 'bag') return 'bags';
    if (u == 'piece' || u == 'pcs') return 'pieces';
    if (u == 'box') return 'boxes';
    if (u == 'tin') return 'tins';
    return u;
  }

  Widget _row(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
