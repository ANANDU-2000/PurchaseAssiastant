import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/stock_providers.dart';
import 'operational_stock_filter_sheet.dart';

export 'operational_stock_filter_sheet.dart'
    show
        showOperationalStockFilter,
        kOperationalDesktopBreakpoint,
        stockActiveFilterSummary;

/// Legacy entry — opens unified operational filter sheet/panel.
Future<void> showStockFilterBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required StockListQuery initial,
  required TextEditingController subcategoryCtrl,
}) {
  return showOperationalStockFilter(
    context: context,
    ref: ref,
    subcategoryCtrl: subcategoryCtrl,
  );
}

bool stockHasActiveFilters(StockListQuery q, StockOperationalFilters op) =>
    countOperationalActiveFilters(q, op) > 0;
