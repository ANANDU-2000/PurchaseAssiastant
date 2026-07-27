import '../json_coerce.dart';
import '../providers/home_dashboard_provider.dart';

/// Parses the event timestamp from a `/stock/audit/recent` row (API: `updated_at`).
DateTime? parseStockAuditTimestamp(Map<String, dynamic> row) {
  for (final key in [
    'updated_at',
    'created_at',
    'audited_at',
    'at',
    'on',
  ]) {
    final raw = row[key];
    if (raw == null) continue;
    final parsed = DateTime.tryParse(raw.toString());
    if (parsed != null) return parsed.toLocal();
  }
  return null;
}

/// Signed qty change from audit row (`new_qty - old_qty`, or legacy `qty_delta`).
double stockAuditQtyDelta(Map<String, dynamic> row) {
  final legacy = row['qty_delta'] ?? row['delta'];
  if (legacy != null) {
    return coerceToDouble(legacy);
  }
  return coerceToDouble(row['new_qty']) - coerceToDouble(row['old_qty']);
}

/// Half-open local window `[start, end)` — matches [homePeriodRange].
bool stockAuditTimestampInPeriod(
  DateTime atLocal,
  ({DateTime start, DateTime end}) range,
) {
  return !atLocal.isBefore(range.start) && atLocal.isBefore(range.end);
}

List<Map<String, dynamic>> filterStockAuditRowsByHomePeriod(
  List<Map<String, dynamic>> rows,
  HomePeriod period, {
  DateTime? now,
  ({DateTime start, DateTime endInclusive})? custom,
}) {
  final range = homePeriodRange(period, now: now, custom: custom);
  final out = <Map<String, dynamic>>[];
  for (final raw in rows) {
    final m = Map<String, dynamic>.from(raw);
    final at = parseStockAuditTimestamp(m);
    if (at == null) continue;
    if (!stockAuditTimestampInPeriod(at, range)) continue;
    out.add(m);
  }
  return out;
}

List<Map<String, dynamic>> filterStockAuditRowsOnLocalDay(
  List<Map<String, dynamic>> rows,
  DateTime dayLocal,
) {
  final d = DateTime(dayLocal.year, dayLocal.month, dayLocal.day);
  return rows.where((raw) {
    final at = parseStockAuditTimestamp(Map<String, dynamic>.from(raw));
    if (at == null) return false;
    final local = DateTime(at.year, at.month, at.day);
    return local == d;
  }).map((e) => Map<String, dynamic>.from(e)).toList();
}

/// Purchase bills as audit-shaped rows for stock **Changes** / **Today** feeds.
List<Map<String, dynamic>> mapPurchasesToStockAuditRows(
  List<Map<String, dynamic>> purchases,
) {
  final out = <Map<String, dynamic>>[];
  for (final raw in purchases) {
    final p = Map<String, dynamic>.from(raw);
    final atRaw =
        p['purchase_date']?.toString() ?? p['created_at']?.toString();
    final at = atRaw != null ? DateTime.tryParse(atRaw) : null;
    if (at == null) continue;
    out.add({
      'adjustment_type': 'purchase',
      'item_name': p['supplier_name']?.toString() ?? 'Purchase bill',
      'unit': '',
      'old_qty': 0,
      'new_qty': 0,
      'qty_delta': 0,
      'reason': p['human_id']?.toString() ??
          p['invoice_number']?.toString() ??
          'Bill',
      'updated_at': at.toUtc().toIso8601String(),
      'updated_by_name': p['created_by_name']?.toString() ??
          p['entered_by_name']?.toString(),
      'purchase_total_inr': p['total_amount'] ?? p['bill_total'],
    });
  }
  return out;
}

List<Map<String, dynamic>> sortStockAuditRowsNewestFirst(
  List<Map<String, dynamic>> rows,
) {
  final copy = rows.map((e) => Map<String, dynamic>.from(e)).toList();
  copy.sort((a, b) {
    final ta = parseStockAuditTimestamp(a) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final tb = parseStockAuditTimestamp(b) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return tb.compareTo(ta);
  });
  return copy;
}
