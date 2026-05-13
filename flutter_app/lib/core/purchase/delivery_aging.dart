import 'package:flutter/material.dart';

import '../models/trade_purchase_models.dart';

/// Calendar days from [purchaseDate] (local midnight) to today (local midnight).
int undeliveredDaysSincePurchase(TradePurchase p) {
  final pur = DateTime(
    p.purchaseDate.year,
    p.purchaseDate.month,
    p.purchaseDate.day,
  );
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return today.difference(pur).inDays;
}

/// Visual priority for **goods not yet received** (undelivered), by age since bill date.
/// Payment/due-date overdue continues to use purchase status chips elsewhere.
enum UndeliveredAgingBand {
  neutral,
  warning,
  strong,
  critical,
}

/// Escalates faster than before so 1–2 day waits are not easy to miss.
UndeliveredAgingBand undeliveredAgingBandFromDays(int daysSincePurchase) {
  if (daysSincePurchase <= 0) return UndeliveredAgingBand.neutral;
  if (daysSincePurchase <= 2) return UndeliveredAgingBand.warning;
  if (daysSincePurchase <= 6) return UndeliveredAgingBand.strong;
  return UndeliveredAgingBand.critical;
}

({Color bg, Color border, Color fg}) undeliveredAgingColors(UndeliveredAgingBand b) {
  switch (b) {
    case UndeliveredAgingBand.neutral:
      return (
        bg: const Color(0xFFEFFDFA),
        border: const Color(0xFF5EEAD4),
        fg: const Color(0xFF0F766E),
      );
    case UndeliveredAgingBand.warning:
      return (
        bg: const Color(0xFFFFF7ED),
        border: const Color(0xFFFDBA74),
        fg: const Color(0xFF9A3412),
      );
    case UndeliveredAgingBand.strong:
      return (
        bg: const Color(0xFFFFEDD5),
        border: const Color(0xFFEA580C),
        fg: const Color(0xFF7C2D12),
      );
    case UndeliveredAgingBand.critical:
      return (
        bg: const Color(0xFFFEF2F2),
        border: const Color(0xFFEF4444),
        fg: const Color(0xFF7F1D1D),
      );
  }
}

Color? undeliveredLeftStripeColor(UndeliveredAgingBand b) {
  switch (b) {
    case UndeliveredAgingBand.neutral:
      return null;
    case UndeliveredAgingBand.warning:
      return const Color(0xFFF97316);
    case UndeliveredAgingBand.strong:
      return const Color(0xFFEA580C);
    case UndeliveredAgingBand.critical:
      return const Color(0xFFDC2626);
  }
}

IconData undeliveredAgingIcon(UndeliveredAgingBand b) {
  switch (b) {
    case UndeliveredAgingBand.neutral:
      return Icons.schedule_rounded;
    case UndeliveredAgingBand.warning:
      return Icons.hourglass_top_rounded;
    case UndeliveredAgingBand.strong:
      return Icons.warning_amber_rounded;
    case UndeliveredAgingBand.critical:
      return Icons.error_outline_rounded;
  }
}

String undeliveredAgingChipLabel(int waitDays, UndeliveredAgingBand b) {
  final age = waitDays <= 0 ? 'today' : '${waitDays}d';
  return switch (b) {
    UndeliveredAgingBand.neutral => 'Awaiting · $age',
    UndeliveredAgingBand.warning => 'Undelivered · $age',
    UndeliveredAgingBand.strong => 'Late · $age',
    UndeliveredAgingBand.critical => 'Very late · $age',
  };
}

/// Active undelivered row (not deleted/cancelled); null if delivered or inactive.
UndeliveredAgingBand? undeliveredAgingBandForPurchase(TradePurchase p) {
  if (p.isDelivered) return null;
  final st = p.statusEnum;
  if (st == PurchaseStatus.deleted || st == PurchaseStatus.cancelled) {
    return null;
  }
  final d = undeliveredDaysSincePurchase(p);
  return undeliveredAgingBandFromDays(d);
}
