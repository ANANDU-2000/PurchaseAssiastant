import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../reporting/reports_item_metrics.dart';

/// Compact trader-focused row: index, name, qty line, rate line, total.
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

  static String _inr0(num n) =>
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
          .format(n);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final qtyLine = reportQtySummaryBoldLine(row);
    final showAmt = row.amountInr > 1e-6;
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
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  if (qtyLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      qtyLine,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: Color(0xFF0D9488),
                      ),
                    ),
                  ],
                  if (rateLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      rateLine,
                      style: TextStyle(
                        fontSize: 11,
                        color: HexaColors.textBody,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showAmt)
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Text(
                  _inr0(row.amountInr),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0D9488),
                  ),
                ),
              ),
            Icon(Icons.chevron_right_rounded,
                color: HexaColors.textBody.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
