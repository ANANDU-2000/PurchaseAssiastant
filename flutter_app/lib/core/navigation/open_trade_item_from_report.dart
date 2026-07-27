import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'resolve_catalog_item_id.dart';

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
    cid = await resolveCatalogItemId(ref, itemName: name) ?? '';
  }
  if (!context.mounted) return;
  if (cid.isNotEmpty) {
    context.push('/catalog/item/$cid/ledger');
  } else {
    context.push('/item-analytics/${Uri.encodeComponent(name)}');
  }
}

/// Opens unified item detail (or analytics fallback) from reports rows.
Future<void> openCatalogItemFromReportRow(
  BuildContext context,
  WidgetRef ref,
  Map<String, dynamic> row, {
  String tab = 'purchases',
}) async {
  final name = row['item_name']?.toString() ?? '';
  if (name.trim().isEmpty) return;
  var cid = row['catalog_item_id']?.toString().trim() ?? '';
  if (cid.isEmpty) {
    cid = await resolveCatalogItemId(ref, itemName: name) ?? '';
  }
  if (!context.mounted) return;
  if (cid.isNotEmpty) {
    context.push('/catalog/item/$cid?tab=$tab');
  } else {
    context.push('/item-analytics/${Uri.encodeComponent(name)}');
  }
}
