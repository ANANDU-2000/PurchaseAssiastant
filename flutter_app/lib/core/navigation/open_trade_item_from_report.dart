import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/catalog_providers.dart';

/// Prefer `/catalog/item/:id/ledger` (bills, search, PDF, edit). Falls back to
/// `/item-analytics/:name` when no catalog id is known.
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
      final want = name.trim().toLowerCase();
      for (final m in list) {
        final n = (m['name'] ?? '').toString().trim().toLowerCase();
        if (n == want) {
          cid = m['id']?.toString().trim() ?? '';
          break;
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
