import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'stock_sheet_launch.dart';
import 'widgets/stock_update_mode_toggle.dart';

/// Opens the unified stock sheet (physical count vs system ledger edit).
Future<void> showUpdateStockSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String itemId,
  required String itemName,
  Map<String, dynamic>? stockRow,
  StockUpdateMode initialMode = StockUpdateMode.physical,
}) async {
  await openQuickStockWithFreshItem(
    context: context,
    ref: ref,
    itemId: itemId,
    itemName: itemName,
    fallbackRow: stockRow,
    initialMode: initialMode,
  );
}
