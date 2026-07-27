import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/catalog_providers.dart';
import '../providers/home_dashboard_provider.dart';
import '../providers/home_breakdown_tab_providers.dart';

String normCatalogItemName(String s) =>
    s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

/// Resolves a catalog item UUID from explicit id, display name, or home/report rows.
Future<String?> resolveCatalogItemId(
  WidgetRef ref, {
  String? itemId,
  String? itemName,
}) async {
  final direct = itemId?.trim() ?? '';
  if (direct.isNotEmpty) return direct;

  final name = itemName?.trim() ?? '';
  if (name.isEmpty) return null;

  final want = normCatalogItemName(name);

  final dash = ref.read(homeDashboardDataProvider).snapshot.data;
  for (final s in dash.itemSlices) {
    if (normCatalogItemName(s.name) != want) continue;
    final id = s.catalogItemId?.trim();
    if (id != null && id.isNotEmpty) return id;
  }

  final shell = ref.read(homeShellReportsSyncCacheProvider);
  if (shell != null) {
    for (final m in shell.items) {
      if (normCatalogItemName(m['item_name']?.toString() ?? '') != want) {
        continue;
      }
      final id = m['catalog_item_id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }
  }

  try {
    final list = await ref.read(catalogItemsListProvider.future);
    for (final m in list) {
      if (normCatalogItemName((m['name'] ?? '').toString()) == want) {
        final id = m['id']?.toString().trim();
        if (id != null && id.isNotEmpty) return id;
      }
    }
    for (final m in list) {
      final n = normCatalogItemName((m['name'] ?? '').toString());
      if (want.isNotEmpty &&
          (n.contains(want) || want.contains(n)) &&
          (m['id']?.toString() ?? '').trim().isNotEmpty) {
        return m['id']!.toString().trim();
      }
    }
  } catch (_) {}

  return null;
}
