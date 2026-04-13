import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart';

/// Recent purchases + frequency + last supplier per catalog item (client-side from entry history).
class EntryQuickPicks {
  const EntryQuickPicks({
    required this.recentLines,
    required this.topLines,
    required this.lastSupplierByCatalogItemId,
  });

  /// Line maps from history (newest purchases first — unique items).
  final List<Map<String, dynamic>> recentLines;

  /// Same shape, ordered by how often the item appeared in the window.
  final List<Map<String, dynamic>> topLines;

  final Map<String, String> lastSupplierByCatalogItemId;

  String? lastSupplierForCatalog(String? catalogItemId) {
    if (catalogItemId == null || catalogItemId.isEmpty) return null;
    return lastSupplierByCatalogItemId[catalogItemId];
  }
}

final entryQuickPicksProvider =
    FutureProvider.autoDispose.family<EntryQuickPicks, String>((ref, businessId) async {
  final api = ref.read(hexaApiProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  final to = DateTime.now();
  final from = to.subtract(const Duration(days: 120));
  final raw = await api.listEntries(
    businessId: businessId,
    from: fmt.format(from),
    to: fmt.format(to),
  );
  return _computeQuickPicks(raw);
});

String _lineKey(Map<String, dynamic> li) {
  final cid = li['catalog_item_id']?.toString();
  final name = (li['item_name']?.toString() ?? '').trim();
  if (cid != null && cid.isNotEmpty) return 'id:$cid';
  if (name.isNotEmpty) return 'n:${name.toLowerCase()}';
  return '';
}

EntryQuickPicks _computeQuickPicks(List<dynamic> raw) {
  final lastSupplierByCatalogItemId = <String, String>{};
  final recentLines = <Map<String, dynamic>>[];
  final seenRecent = <String>{};
  final counts = <String, int>{};
  final lineByKey = <String, Map<String, dynamic>>{};

  // Entries are newest-first from API.
  for (final e in raw) {
    if (e is! Map) continue;
    final sup = e['supplier_id']?.toString();
    final lines = e['lines'];
    if (lines is! List) continue;

    for (final li in lines) {
      if (li is! Map) continue;
      final m = Map<String, dynamic>.from(li);
      final key = _lineKey(m);
      if (key.isEmpty) continue;

      final cid = m['catalog_item_id']?.toString();
      if (cid != null &&
          cid.isNotEmpty &&
          sup != null &&
          sup.isNotEmpty &&
          !lastSupplierByCatalogItemId.containsKey(cid)) {
        lastSupplierByCatalogItemId[cid] = sup;
      }

      counts[key] = (counts[key] ?? 0) + 1;
      lineByKey[key] = m;

      if (!seenRecent.contains(key)) {
        seenRecent.add(key);
        recentLines.add(m);
      }
    }
  }

  final sortedKeys = counts.keys.toList()
    ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
  final topLines = <Map<String, dynamic>>[];
  for (final k in sortedKeys.take(10)) {
    final li = lineByKey[k];
    if (li != null) topLines.add(li);
  }

  return EntryQuickPicks(
    recentLines: recentLines.take(12).toList(),
    topLines: topLines,
    lastSupplierByCatalogItemId: lastSupplierByCatalogItemId,
  );
}
