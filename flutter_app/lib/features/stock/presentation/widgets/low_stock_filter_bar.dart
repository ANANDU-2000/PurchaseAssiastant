import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_responsive.dart';

enum LowStockOpsFilter {
  all,
  low,
  out,
  pending,
  delayed,
  disputed,
  verification,
  urgent,
  highSalesImpact,
}

extension LowStockOpsFilterX on LowStockOpsFilter {
  String get label => switch (this) {
        LowStockOpsFilter.all => 'ALL',
        LowStockOpsFilter.low => 'LOW',
        LowStockOpsFilter.out => 'OUT',
        LowStockOpsFilter.pending => 'PENDING',
        LowStockOpsFilter.delayed => 'DELAYED',
        LowStockOpsFilter.disputed => 'DISPUTED',
        LowStockOpsFilter.verification => 'VERIFICATION',
        LowStockOpsFilter.urgent => 'URGENT',
        LowStockOpsFilter.highSalesImpact => 'HIGH_SALES',
      };
}

class LowStockFilterBar extends StatelessWidget {
  const LowStockFilterBar({
    super.key,
    required this.active,
    required this.onActiveChanged,
    this.bulkMode = false,
    this.onBulkModeChanged,
    this.selectedCount = 0,
  });

  final LowStockOpsFilter active;
  final ValueChanged<LowStockOpsFilter> onActiveChanged;
  final bool bulkMode;
  final ValueChanged<bool>? onBulkModeChanged;
  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    const chips = [
      LowStockOpsFilter.all,
      LowStockOpsFilter.low,
      LowStockOpsFilter.out,
      LowStockOpsFilter.pending,
      LowStockOpsFilter.delayed,
      LowStockOpsFilter.disputed,
      LowStockOpsFilter.verification,
      LowStockOpsFilter.urgent,
      LowStockOpsFilter.highSalesImpact,
    ];

    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const SizedBox(width: 8),
            if (onBulkModeChanged != null) ...[
              FilterChip(
                label: Text(bulkMode ? 'Bulk ($selectedCount)' : 'Bulk'),
                selected: bulkMode,
                onSelected: onBulkModeChanged,
              ),
              const SizedBox(width: 8),
            ],
            for (final c in chips) ...[
              HexaAccessibleFilterChip(
                label: c.label,
                selected: c == active,
                compact: true,
                onSelected: (v) {
                  if (!v) return;
                  onActiveChanged(c);
                },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

