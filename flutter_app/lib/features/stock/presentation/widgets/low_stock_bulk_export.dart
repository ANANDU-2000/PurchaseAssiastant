import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Export selected low-stock rows as CSV (clipboard on web, snackbar elsewhere).
Future<void> exportLowStockSelectionCsv(
  BuildContext context, {
  required List<Map<String, dynamic>> items,
}) async {
  if (items.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Select items to export')),
    );
    return;
  }

  final buf = StringBuffer(
    'name,category,subcategory,system_stock,physical_stock,diff,lifecycle,priority_band,supplier\n',
  );
  for (final item in items) {
    final cols = [
      item['name'],
      item['category_name'],
      item['subcategory_name'],
      item['current_stock'],
      item['physical_stock_qty'] ?? item['current_stock'],
      item['physical_stock_difference_qty'] ?? item['warehouse_diff_qty'],
      item['lifecycle_stage'],
      item['priority_band'],
      item['supplier_name'],
    ];
    buf.writeln(cols.map(_csvEscape).join(','));
  }

  final csv = buf.toString();
  if (kIsWeb) {
    await Clipboard.setData(ClipboardData(text: csv));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${items.length} rows to clipboard')),
    );
    return;
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('CSV ready (${items.length} rows) — share from item export on mobile'),
      duration: const Duration(seconds: 4),
    ),
  );
  debugPrint(csv);
}

String _csvEscape(Object? v) {
  final s = (v ?? '').toString().replaceAll('"', '""');
  if (s.contains(',') || s.contains('\n')) return '"$s"';
  return s;
}
