import 'package:flutter/material.dart';

import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../reporting/reports_item_metrics.dart';

/// Compact trader-focused row: index, name, qty line, rate line (no row total ₹).
class ReportsItemTile extends StatelessWidget {
  const ReportsItemTile({
    super.key,
    required this.index,
    required this.row,
    required this.rateLine,
    required this.onTap,
  });

  final int index;
  final TradeReportItemRow row;
  final String rateLine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final qtyLine = reportQtySummaryBoldLine(row);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '$index.',
                style: tt.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: HexaColors.textBody,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.name,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  if (qtyLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      qtyLine,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ],
                  if (rateLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      rateLine,
                      style: tt.bodySmall?.copyWith(
                        color: HexaColors.textBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: HexaColors.textBody.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
