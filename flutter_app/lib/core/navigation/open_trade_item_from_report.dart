import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/catalog_providers.dart';

/// Opens `/catalog/item/:id/ledger` (trade ledger: bills, search, PDF).
/// Falls back to `/item-analytics/:name` when no catalog id is known.
Future<void> openTradeItemFromReportRow(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> row,
) async {
  final name = row['item_name']?.toString() ?? '';
  if (name.trim().isEmpty) return;
  var cid = row['catalog_item_id']?.toString().trim() ?? '';
  if (cid.isEmpty) {
    try {
      final list = await ref.read(catalogItemsListProvider.future);
      String norm(String s) =>
          s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      final want = norm(name);
      for (final m in list) {
        final n = norm((m['name'] ?? '').toString());
        if (n == want) {
          cid = m['id']?.toString().trim() ?? '';
          break;
        }
      }
      if (cid.isEmpty) {
        for (final m in list) {
          final n = norm((m['name'] ?? '').toString());
          if (want.isNotEmpty &&
              (n.contains(want) || want.contains(n)) &&
              (m['id']?.toString() ?? '').trim().isNotEmpty) {
            cid = m['id']!.toString().trim();
            break;
          }
        }
      }
    } catch (_) {}
  }
  if (!context.mounted) return;
  if (cid.isNotEmpty) {
    context.push('/catalog/item/$cid/ledger');
  } else {
    context.push('/item-analytics/${Uri.encodeComponent(name)}');
  }
}
