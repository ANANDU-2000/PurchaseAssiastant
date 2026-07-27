import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/hexa_colors.dart';

/// Outcome of comparing last landed unit cost to rolling trade average.
class TradeBuyVerdict {
  const TradeBuyVerdict({
    required this.label,
    required this.detail,
    required this.accent,
  });

  final String label;
  final String detail;
  final Color accent;
}

/// Verdict: last landed vs `avg_landing_from_trade` (and optional `bestLatest` for copy only).
///
/// - NO DATA: missing last landed or trade average
/// - GOOD: `lastLanded <= tradeAvg` (epsilon)
/// - OK: `lastLanded <= tradeAvg * 1.05` and not GOOD
/// - BAD: else
TradeBuyVerdict tradeBuyVerdict({
  required double? lastLanded,
  required double? tradeAvg,
  double? bestLatest,
  NumberFormat? inrFormat,
}) {
  final inr = inrFormat ??
      NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 0,
      );
  if (lastLanded == null || tradeAvg == null) {
    return const TradeBuyVerdict(
      label: 'NO DATA',
      detail:
          'Need a latest landed price and a rolling trade average. Record more confirmed purchases for this item.',
      accent: HexaColors.textSecondary,
    );
  }
  const eps = 1e-6;
  final avg = tradeAvg;
  if (lastLanded <= avg + eps) {
    return TradeBuyVerdict(
      label: 'GOOD',
      detail:
          'Last landed is at or below your trade average (${inr.format(avg)} / unit).',
      accent: HexaColors.profit,
    );
  }
  if (lastLanded <= avg * 1.05 + eps) {
    var detail =
        'Within 5% above your trade average (${inr.format(avg)} / unit) — still acceptable; negotiate toward average if you can.';
    if (bestLatest != null) {
      detail +=
          ' Best latest supplier quote: ${inr.format(bestLatest)} / unit.';
    }
    return TradeBuyVerdict(
      label: 'OK',
      detail: detail,
      accent: HexaColors.accentInfo,
    );
  }
  var badDetail =
      'Last landed is more than 5% above your trade average (${inr.format(avg)} / unit). Re-quote or try another supplier.';
  if (bestLatest != null) {
    badDetail +=
        ' Cheapest latest quote in list: ${inr.format(bestLatest)} / unit.';
  }
  return TradeBuyVerdict(
    label: 'BAD',
    detail: badDetail,
    accent: HexaColors.warning,
  );
}
