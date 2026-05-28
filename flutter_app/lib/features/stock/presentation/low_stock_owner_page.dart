import 'package:flutter/material.dart';

import 'low_stock_dashboard_page.dart';

/// @deprecated Use [LowStockDashboardPage] via `/stock/low-stock`.
@Deprecated('Use LowStockDashboardPage(staffMode: false)')
class LowStockOwnerPage extends StatelessWidget {
  const LowStockOwnerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LowStockDashboardPage(staffMode: false);
  }
}
