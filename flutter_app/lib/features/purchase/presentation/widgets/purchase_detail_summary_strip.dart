import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Compact Amount | Weight | Profit summary strip.
class PurchaseDetailSummaryStrip extends StatelessWidget {
  const PurchaseDetailSummaryStrip({
    super.key,
    required this.amountLabel,
    required this.weightPrimary,
    required this.weightSecondary,
    required this.profitLabel,
    required this.profitColor,
  });

  final String amountLabel;
  final String weightPrimary;
  final String? weightSecondary;
  final String profitLabel;
  final Color profitColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget col(String label, String value, Color valueColor, {String? sub}) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: Color(0xFF888888),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: valueColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (sub != null && sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8D5D0)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            col('AMOUNT', amountLabel, cs.onSurface),
            VerticalDivider(width: 1, color: Colors.grey.shade200),
            col(
              'WEIGHT',
              weightPrimary,
              cs.onSurface,
              sub: weightSecondary,
            ),
            VerticalDivider(width: 1, color: Colors.grey.shade200),
            col('PROFIT', profitLabel, profitColor),
          ],
        ),
      ),
    );
  }
}

/// Formats weight totals for summary strip (uppercase units).
String formatPurchaseSummaryWeight({
  required double totalKg,
  required double totalBags,
  required double totalBox,
  required double totalTin,
}) {
  final kgFmt = NumberFormat('#,##0.##', 'en_IN');
  final parts = <String>[];
  if (totalKg > 1e-6) {
    parts.add('${kgFmt.format(totalKg)} KG');
  }
  if (totalBags > 1e-6) {
    parts.add('${kgFmt.format(totalBags)} BAG');
  }
  if (totalBox > 1e-6) {
    parts.add('${kgFmt.format(totalBox)} BOX');
  }
  if (totalTin > 1e-6) {
    parts.add('${kgFmt.format(totalTin)} TIN');
  }
  if (parts.isEmpty) return '—';
  if (parts.length == 1) return parts.first;
  return parts.join(' + ');
}

String? formatPurchaseSummaryWeightSecondary({
  required double totalKg,
  required double totalBags,
  required double totalBox,
  required double totalTin,
}) {
  final kgFmt = NumberFormat('#,##0.##', 'en_IN');
  final parts = <String>[];
  if (totalKg > 1e-6) parts.add('${kgFmt.format(totalKg)} KG');
  if (totalBags > 1e-6) parts.add('${kgFmt.format(totalBags)} BAG');
  if (totalBox > 1e-6) parts.add('${kgFmt.format(totalBox)} BOX');
  if (totalTin > 1e-6) parts.add('${kgFmt.format(totalTin)} TIN');
  if (parts.length <= 1) return null;
  return parts.sublist(1).join(' · ');
}
