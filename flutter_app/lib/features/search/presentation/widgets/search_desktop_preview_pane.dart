import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../catalog/presentation/widgets/item_stock_snapshot_card.dart';

/// Desktop search right pane — item snapshot + open detail.
class SearchDesktopPreviewPane extends StatelessWidget {
  const SearchDesktopPreviewPane({
    super.key,
    required this.itemId,
    this.itemName,
  });

  final String? itemId;
  final String? itemName;

  @override
  Widget build(BuildContext context) {
    if (itemId == null || itemId!.isEmpty) {
      return const ColoredBox(
        color: Color(0xFFFAFAF8),
        child: Center(
          child: Text(
            'Select a catalog item',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
      );
    }
    final name = itemName?.trim() ?? 'Item';
    return ColoredBox(
      color: const Color(0xFFFAFAF8),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            name,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ItemStockSnapshotCard(itemId: itemId!),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.push('/catalog/item/$itemId'),
            child: const Text('Open full item'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.push('/catalog/item/$itemId/edit'),
            child: const Text('Edit item'),
          ),
        ],
      ),
    );
  }
}
