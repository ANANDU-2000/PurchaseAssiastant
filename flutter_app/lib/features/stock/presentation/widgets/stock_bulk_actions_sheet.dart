import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import 'stock_bulk_archive_sheet.dart';

void showStockBulkActionsSheet({
  required BuildContext context,
  required WidgetRef ref,
}) {
  showHexaBottomSheet<void>(
    context: context,
    compact: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.print_outlined),
          title: const Text('Bulk barcode print'),
          onTap: () {
            Navigator.pop(context);
            context.push('/barcode/bulk-print');
          },
        ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: const Text('Setup reorder levels'),
          onTap: () {
            Navigator.pop(context);
            context.push('/catalog/setup-reorder-levels');
          },
        ),
        ListTile(
          leading: const Icon(Icons.copy_all_outlined),
          title: const Text('Review duplicate items'),
          onTap: () {
            Navigator.pop(context);
            context.push('/catalog/duplicates');
          },
        ),
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Bulk archive'),
          onTap: () {
            Navigator.pop(context);
            showStockBulkArchiveSheet(context: context, ref: ref);
          },
        ),
      ],
    ),
  );
}
