import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/providers/home_dashboard_provider.dart';
import '../../../../core/providers/home_owner_dashboard_providers.dart';
import '../../../../core/theme/hexa_colors.dart';
import 'home_analytics_helpers.dart';
import 'home_formatters.dart';

/// Compact two-column strip: on-hand (live stock) vs purchased (selected period).
class HomeInventorySummaryStrip extends StatelessWidget {
  const HomeInventorySummaryStrip({
    super.key,
    required this.inventory,
    required this.dashboard,
    this.inventoryLoading = false,
    this.purchasedLoading = false,
  });

  final HomeInventorySummary inventory;
  final HomeDashboardData dashboard;
  final bool inventoryLoading;
  final bool purchasedLoading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HexaColors.brandBorder.withValues(alpha: 0.7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _column(
            context,
            title: 'Stock in hand',
            line: inventoryLoading ? '…' : inventoryUnitsLine(inventory),
            trailing: null,
          )),
          Container(
            width: 1,
            height: 44,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            color: HexaColors.brandBorder.withValues(alpha: 0.5),
          ),
          Expanded(
            child: _column(
              context,
              title: 'Purchased',
              line: purchasedLoading
                  ? '…'
                  : purchasedUnitsLine(dashboard),
              trailing: purchasedLoading
                  ? null
                  : homeInr(dashboard.totalPurchase),
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(
    BuildContext context, {
    required String title,
    required String line,
    String? trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: HexaDsType.labelCaps(context).copyWith(
            fontSize: 9,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          line,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: HexaDsType.bodySm(context).copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            height: 1.25,
          ),
        ),
        if (trailing != null && trailing.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            trailing,
            style: HexaDsType.bodySm(context).copyWith(
              fontWeight: FontWeight.w800,
              color: HexaColors.brandPrimary,
            ),
          ),
        ],
      ],
    );
  }
}
