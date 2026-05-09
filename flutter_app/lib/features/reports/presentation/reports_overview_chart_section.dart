import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../../../core/reporting/trade_report_aggregate.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../widgets/spend_ring_chart.dart';

String _inr0(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// Pack-channel split of landing INR (proportional when a row mixes bags/boxes/tins).
({List<double> values, List<Color> colors}) _packMixSlices(TradeReportAgg agg) {
  const cols = [
    Color(0xFF0D9488),
    Color(0xFF6366F1),
    Color(0xFFEA580C),
    Color(0xFF94A3B8),
  ];
  var bag = 0.0;
  var box = 0.0;
  var tin = 0.0;
  var other = 0.0;
  for (final r in agg.itemsAll) {
    final den = r.bags + r.boxes + r.tins;
    final amt = r.amountInr;
    if (amt <= 1e-9) continue;
    if (den < 1e-9) {
      other += amt;
      continue;
    }
    bag += amt * (r.bags / den);
    box += amt * (r.boxes / den);
    tin += amt * (r.tins / den);
  }
  final raw = [bag, box, tin, other];
  final vals = <double>[];
  final colors = <Color>[];
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] > 1e-9) {
      vals.add(raw[i]);
      colors.add(cols[i]);
    }
  }
  if (vals.isEmpty) {
    return (values: [1.0], colors: [const Color(0xFFCBD5E1)]);
  }
  return (values: vals, colors: colors);
}

/// Overview-only: adaptive donut (max ~35% viewport height), shimmer loading, empty actions.
class ReportsOverviewChartSection extends StatelessWidget {
  const ReportsOverviewChartSection({
    super.key,
    required this.agg,
    required this.viewportHeight,
    required this.isLoadingInitial,
    required this.isEmpty,
    required this.canRetry,
    required this.onRetry,
    required this.onMatchHome,
    required this.onPickRange,
  });

  final TradeReportAgg agg;
  final double viewportHeight;
  final bool isLoadingInitial;
  final bool isEmpty;
  final bool canRetry;
  final VoidCallback onRetry;
  final VoidCallback onMatchHome;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
    final maxD = math.min(viewportHeight * 0.35, 240.0);
    final width = MediaQuery.sizeOf(context).width - 48;
    final diameter = math.min(maxD, width * 0.78).clamp(120.0, maxD);

    if (isLoadingInitial) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: SizedBox(
            height: diameter,
            child: Center(
              child: Container(
                width: diameter,
                height: diameter,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (isEmpty) {
      final smallRing = diameter * 0.72;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SpendRingChart(
                diameter: smallRing,
                strokeWidth: 7,
                values: const [1],
                colors: const [Color(0xFFE2E8F0)],
                centerChild: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_outlined,
                        size: 30, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    Text(
                      'No purchases in selected range',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        height: 1.25,
                        color: HexaColors.textBody,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: canRetry ? onRetry : null,
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: canRetry ? onMatchHome : null,
              child: const Text('Match Home period'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: canRetry ? onPickRange : null,
              child: const Text('Change period'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => context.pushNamed('purchase_scan'),
              icon: const Icon(Icons.document_scanner_outlined, size: 18),
              label: const Text('Scan purchase bill'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => context.go('/purchase/new'),
              icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
              label: const Text('New purchase'),
            ),
          ],
        ),
      );
    }

    final mix = _packMixSlices(agg);
    final t = agg.totals;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: RepaintBoundary(
          child: SpendRingChart(
            diameter: diameter,
            strokeWidth: math.max(7.0, diameter * 0.045),
            values: mix.values,
            colors: mix.colors,
            centerChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Purchase mix',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey.shade700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _inr0(t.inr.round()),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (t.deals > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${t.deals} classified deals',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
