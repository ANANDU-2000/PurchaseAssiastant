import 'package:flutter/material.dart';

import '../../core/json_coerce.dart';
import '../../core/utils/unit_utils.dart';
import 'stock_number_display.dart';

enum StockSummaryVariant { row, badge, snapshot, scan }

/// Unified stock qty + unit display (delegates to [StockNumberDisplay] / formatters).
class StockSummaryWidget extends StatelessWidget {
  const StockSummaryWidget({
    super.key,
    required this.qty,
    required this.unit,
    this.variant = StockSummaryVariant.row,
    this.status,
    this.compact = false,
    this.hasPendingOrder = false,
    this.pendingDays,
    this.fontSize = 17,
  });

  final double qty;
  final String unit;
  final StockSummaryVariant variant;
  final String? status;
  final bool compact;
  final bool hasPendingOrder;
  final int? pendingDays;
  final double fontSize;

  factory StockSummaryWidget.fromMap(
    Map<String, dynamic> row, {
    StockSummaryVariant variant = StockSummaryVariant.row,
    bool compact = false,
  }) {
    final q = coerceToDouble(row['current_stock']);
    final u = row['stock_unit']?.toString() ??
        row['unit']?.toString() ??
        row['default_unit']?.toString() ??
        '';
    return StockSummaryWidget(
      qty: q,
      unit: u,
      variant: variant,
      status: row['stock_status']?.toString(),
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case StockSummaryVariant.badge:
        return _Badge(qty: qty, unit: unit, status: status);
      case StockSummaryVariant.snapshot:
      case StockSummaryVariant.scan:
        return Text(
          stockDisplayPrimary(qty, unit),
          style: TextStyle(
            fontSize: compact ? 14 : 16,
            fontWeight: FontWeight.w800,
          ),
        );
      case StockSummaryVariant.row:
        return StockNumberDisplay(
          qty: qty,
          unit: unit,
          status: stockDisplayStatusFromApi(status),
          hasPendingOrder: hasPendingOrder,
          pendingDays: pendingDays,
          fontSize: fontSize,
        );
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.qty, required this.unit, this.status});

  final double qty;
  final String unit;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final label = stockDisplayPrimary(qty, unit);
    Color bg = const Color(0xFFE8F5E9);
    Color fg = const Color(0xFF2E7D32);
    switch (status) {
      case 'low':
        bg = const Color(0xFFFFF3E0);
        fg = const Color(0xFFEF6C00);
      case 'critical':
      case 'out':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFC62828);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}
