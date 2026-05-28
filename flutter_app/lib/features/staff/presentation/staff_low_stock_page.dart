import 'package:flutter/material.dart';

import '../../stock/presentation/low_stock_dashboard_page.dart';

/// @deprecated Use [LowStockDashboardPage] via `/staff/low-stock`.
@Deprecated('Use LowStockDashboardPage(staffMode: true)')
class StaffLowStockPage extends StatelessWidget {
  const StaffLowStockPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LowStockDashboardPage(staffMode: true);
  }
}
