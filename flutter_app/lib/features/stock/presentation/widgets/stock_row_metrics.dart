import 'package:flutter/material.dart';

import '../../../../core/json_coerce.dart';
import '../../../../core/utils/unit_utils.dart';
import '../../../../shared/widgets/stock_number_display.dart';

/// Warehouse table metric formatting (system / purchased / physical / diff / pending).
abstract final class StockRowMetrics {
  static double? purchasedQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['period_purchased_qty']);

  static double? physicalQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['physical_stock_qty']);

  static double? pendingDeliveryQty(Map<String, dynamic> item) =>
      coerceToDoubleNullable(item['pending_delivery_qty']);

  static double stockQty(Map<String, dynamic> item) {
    // Stock column must show backend system/on-hand stock truth.
    // Physical count is displayed separately in item snapshot/workflows.
    return coerceToDouble(item['current_stock']);
  }

  static double diffQty(Map<String, dynamic> item) {
    final wh = coerceToDoubleNullable(item['warehouse_diff_qty']);
    if (wh != null && wh.isFinite) return wh;
    final phys = physicalQty(item);
    if (phys != null && phys.isFinite) {
      return phys - stockQty(item);
    }
    return double.nan;
  }

  static String openingLabel(Map<String, dynamic> item) {
    final opening = coerceToDoubleNullable(item['opening_stock_qty']);
    if (opening == null) return '';
    final u = unit(item);
    return 'Open ${formatStockQtyNumber(opening)}${u.isNotEmpty ? ' $u' : ''}';
  }

  static String deliveryMetaLine(Map<String, dynamic> item) {
    final parts = <String>[];
    final pendingDel = pendingDeliveryQty(item) ?? 0;
    final hasPending = item['has_pending_order'] == true;
    final delivered = item['last_purchase_delivered'] == true;
    final po = item['last_purchase_human_id']?.toString().trim();
    final days = (item['pending_order_days'] as num?)?.toInt();

    if (hasPending || pendingDel > 0.001) {
      var line = 'Pending truck';
      if (pendingDel > 0.001) {
        line += ' ${formatStockQtyNumber(pendingDel)}';
      }
      if (days != null && days > 0) line += ' · ${days}d';
      if (po != null && po.isNotEmpty) line += ' · $po';
      parts.add(line);
    } else if (delivered) {
      parts.add('Delivered${po != null && po.isNotEmpty ? ' · $po' : ''}');
    }
    return parts.join(' · ');
  }

  static String unit(Map<String, dynamic> item) =>
      (item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'piece')
          .toUpperCase();

  static String qtyLine(double? qty, String unit) {
    if (qty == null || !qty.isFinite) return '—';
    return '${formatStockQtyNumber(qty)}\n$unit';
  }

  static String signedDiffLine(double diff, String unit) {
    if (!diff.isFinite) return '—';
    if (diff.abs() < 0.001) {
      return '0\nBalanced';
    }
    final sign = diff > 0 ? '+' : '';
    final intent = diff > 0 ? 'Excess' : 'Deficit';
    return '$sign${formatStockQtyNumber(diff)} $unit\n$intent';
  }

  static Color diffColor(double diff) {
    if (!diff.isFinite || diff.abs() < 0.001) {
      return const Color(0xFF64748B);
    }
    return diff > 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
  }

  static String inlineStatusLabel(Map<String, dynamic> item) {
    final st = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    return switch (stockDisplayStatusFromApi(st)) {
      StockDisplayStatus.out => 'Out',
      StockDisplayStatus.low => 'Low stock',
      StockDisplayStatus.ok => 'Healthy',
      StockDisplayStatus.normal => 'Healthy',
    };
  }

  static Color inlineStatusColor(Map<String, dynamic> item) {
    final st = (item['stock_status']?.toString() ?? 'healthy').toLowerCase();
    return stockNumberColor(stockDisplayStatusFromApi(st));
  }
}
