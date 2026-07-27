/// Safe coercion for JSON / API map values that may be [num], [String], or null.
/// Prevents `type 'String' is not a subtype of type 'num?'` when backends emit decimals as strings.
library;

double coerceToDouble(Object? v) {
  final n = coerceToDoubleNullable(v);
  return n ?? 0;
}

double? coerceToDoubleNullable(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim().replaceAll(',', '');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
  return double.tryParse(v.toString().trim().replaceAll(',', ''));
}

int coerceToInt(Object? v, {int fallback = 0}) {
  final d = coerceToDoubleNullable(v);
  if (d == null) return fallback;
  return d.round();
}

int? coerceToIntNullable(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final d = coerceToDoubleNullable(v);
  if (d == null) return null;
  return d.round();
}

/// Coerce known stock-detail numeric keys so UI never hits unsafe `as num` casts.
Map<String, dynamic> normalizeStockDetailMap(Map<String, dynamic> row) {
  const keys = [
    'current_stock',
    'physical_stock_qty',
    'opening_stock_qty',
    'reorder_level',
    'period_purchased_qty',
    'total_delivered_qty',
    'physical_stock_difference_qty',
    'warehouse_diff_qty',
    'pending_delivery_qty',
    'total_pending_delivery_qty',
    'period_usage_qty',
    'last_line_qty',
    'kg_per_unit',
    'kg_per_bag',
  ];
  final out = Map<String, dynamic>.from(row);
  for (final k in keys) {
    if (!out.containsKey(k) || out[k] == null) continue;
    final parsed = coerceToDoubleNullable(out[k]);
    if (parsed != null) out[k] = parsed;
  }
  return out;
}
