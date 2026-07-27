import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import '../../../../core/providers/stock_providers.dart';
import 'opening_stock_set_sheet.dart';

Future<void> showOpeningStockRowActions({
  required BuildContext context,
  required WidgetRef ref,
  required Map<String, dynamic> item,
}) async {
  final id = item['id']?.toString() ?? '';
  if (id.isEmpty) return;
  final name = item['name']?.toString() ?? 'Item';

  await showHexaBottomSheet<void>(
    context: context,
    compact: true,
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.inventory_2_outlined,
            label: 'Set Opening Stock',
            onTap: () async {
              Navigator.pop(context);
              final ok = await showOpeningStockSetSheet(
                context: context,
                ref: ref,
                item: item,
              );
              if (ok == true && context.mounted) {
                ref.invalidate(openingStockSetupProvider);
              }
            },
          ),
          _ActionTile(
            icon: Icons.info_outline_rounded,
            label: 'View Item Detail',
            onTap: () {
              Navigator.pop(context);
              context.push('/catalog/item/$id');
            },
          ),
          _ActionTile(
            icon: Icons.history_rounded,
            label: 'View Activity',
            onTap: () {
              Navigator.pop(context);
              context.push(
                '/catalog/item/$id?tab=history&name=${Uri.encodeComponent(name)}',
              );
            },
          ),
          _ActionTile(
            icon: Icons.receipt_long_rounded,
            label: 'View Ledger',
            onTap: () {
              Navigator.pop(context);
              context.push('/catalog/item/$id/ledger');
            },
          ),
        ],
    ),
  );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      dense: true,
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
    );
  }
}

