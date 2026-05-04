import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/reports_provider.dart';
import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../reporting/reports_item_metrics.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(n);

String _kg(num n) {
  if (n < 1e-9) return '0';
  if ((n - n.roundToDouble()).abs() < 1e-6) return '${n.round()}';
  return n.toStringAsFixed(1);
}

/// Drill-down: totals + vertical transaction list for one report item key.
class ReportsItemDetailPage extends ConsumerWidget {
  const ReportsItemDetailPage({
    super.key,
    required this.itemKey,
    required this.itemName,
  });

  final String itemKey;
  final String itemName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merged = ref.watch(reportsPurchasesMergedProvider);
    final txns = reportItemTransactions(merged, itemKey);
    final aggAll = buildTradeReportAgg(merged);
    TradeReportItemRow? sumRow;
    for (final r in aggAll.itemsAll) {
      if (r.key == itemKey) {
        sumRow = r;
        break;
      }
    }
    final qtyLine = sumRow == null ? '' : reportQtySummaryBoldLine(sumRow);
    final sumAmt = sumRow?.amountInr ?? 0.0;

    final df = DateFormat('d MMM');

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: Text(itemName, maxLines: 1, overflow: TextOverflow.ellipsis),
        backgroundColor: HexaColors.brandBackground,
        foregroundColor: HexaColors.brandPrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            'Total',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 6),
          if (qtyLine.isNotEmpty)
            Text(
              qtyLine,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          const SizedBox(height: 4),
          Text(
            _inr0(sumAmt.round()),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 20),
          Text(
            'Transactions',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          if (txns.isEmpty)
            Text(
              'No classified lines for this item in the selected period.',
              style: TextStyle(color: HexaColors.textBody),
            )
          else
            ...List.generate(txns.length, (i) {
              final t = txns[i];
              final sell = t.sellRate != null && t.sellRate! > 0
                  ? _inr0(t.sellRate!.round())
                  : '—';
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${i + 1}. ${df.format(t.date)} — ${t.supplierName}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_kg(t.kg)} kg',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_inr0(t.buyRate.round())} → $sell',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: HexaColors.textBody,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => context.pop(),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}
