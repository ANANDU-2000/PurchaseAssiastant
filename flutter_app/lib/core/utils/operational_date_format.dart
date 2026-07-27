import 'package:intl/intl.dart';

/// DD-MMM-YYYY (e.g. 22-May-2026) for operational UI.
String formatOperationalDate(DateTime dt) {
  return DateFormat('dd-MMM-yyyy').format(dt);
}

String formatOperationalDateFromIso(String? iso) {
  if (iso == null || iso.length < 10) return '—';
  final d = DateTime.tryParse(iso.substring(0, 10));
  if (d == null) return '—';
  return formatOperationalDate(d);
}

/// Compact stock row footer: "10:22am · Rajan".
String formatStockRowUpdateLine({
  String? updatedBy,
  String? updatedAtIso,
}) {
  if (updatedAtIso == null || updatedAtIso.isEmpty) return '';
  final dt = DateTime.tryParse(updatedAtIso);
  if (dt == null) return updatedBy?.trim() ?? '';
  final time = DateFormat('h:mma').format(dt.toLocal()).toLowerCase();
  final by = updatedBy?.trim();
  if (by != null && by.isNotEmpty) return '$time · $by';
  return time;
}

/// e.g. "Last update: Rajan · 10:22am" for legacy screens.
String formatLastStockUpdateLine({
  String? updatedBy,
  String? updatedAtIso,
}) {
  if (updatedAtIso == null || updatedAtIso.isEmpty) return '';
  final dt = DateTime.tryParse(updatedAtIso);
  if (dt == null) return updatedBy?.trim() ?? '';
  final time = DateFormat('h:mma').format(dt.toLocal()).toLowerCase();
  final by = updatedBy?.trim();
  if (by != null && by.isNotEmpty) return 'Last update: $by · $time';
  return 'Last update: $time';
}
