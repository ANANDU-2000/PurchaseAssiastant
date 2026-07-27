import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_notifier.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/business_aggregates_invalidation.dart';
import '../../../../core/providers/catalog_providers.dart';
import '../../../../core/providers/stock_providers.dart';

Future<void> showStockBulkArchiveSheet({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  final blob = ref.read(bulkStockListProvider).valueOrNull;
  final items = [
    for (final row in (blob?['items'] as List? ?? []))
      if (row is Map) Map<String, dynamic>.from(row),
  ];
  if (items.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Load stock list first')),
    );
    return;
  }
  final selected = <String>{};
  await showHexaBottomSheet<void>(
    context: context,
    compact: false,
    padding: EdgeInsets.zero,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: HexaResponsive.adaptiveSheetMaxHeight(context) * 0.85,
      ),
      child: StatefulBuilder(
        builder: (ctx, setLocal) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Bulk archive items',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                    TextButton(
                      onPressed: selected.isEmpty
                          ? null
                          : () async {
                              final session = ref.read(sessionProvider);
                              if (session == null) return;
                              final ids = selected.toList();
                              await ref.read(hexaApiProvider).bulkArchiveCatalogItems(
                                    businessId: session.primaryBusiness.id,
                                    itemIds: ids,
                                  );
                              invalidateWarehouseSurfaces(ref);
                              ref.invalidate(stockListProvider);
                              ref.invalidate(bulkStockListProvider);
                              ref.invalidate(catalogItemsListProvider);
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      ids.length == 1
                                          ? '1 item archived'
                                          : '${ids.length} items archived',
                                    ),
                                  ),
                                );
                              }
                            },
                      child: const Text('Archive'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final row = items[i];
                    final id = row['id']?.toString() ?? '';
                    final name = row['name']?.toString() ?? '—';
                    return CheckboxListTile(
                      value: selected.contains(id),
                      onChanged: id.isEmpty
                          ? null
                          : (v) {
                              setLocal(() {
                                if (v == true) {
                                  selected.add(id);
                                } else {
                                  selected.remove(id);
                                }
                              });
                            },
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(row['item_code']?.toString() ?? ''),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
