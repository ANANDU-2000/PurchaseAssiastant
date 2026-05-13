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

UndeliveredAgingBand undeliveredAgingBandFromDays(int daysSincePurchase) {
  if (daysSincePurchase <= 2) return UndeliveredAgingBand.neutral;
  if (daysSincePurchase <= 5) return UndeliveredAgingBand.warning;
  if (daysSincePurchase <= 9) return UndeliveredAgingBand.strong;
  return UndeliveredAgingBand.critical;
}

({Color bg, Color border, Color fg}) undeliveredAgingColors(UndeliveredAgingBand b) {
  switch (b) {
    case UndeliveredAgingBand.neutral:
      return (
        bg: const Color(0xFFF1F5F9),
        border: const Color(0xFFCBD5E1),
        fg: const Color(0xFF334155),
      );
    case UndeliveredAgingBand.warning:
      return (
        bg: Colors.orange.shade50,
        border: Colors.orange.shade200,
        fg: Colors.orange.shade900,
      );
    case UndeliveredAgingBand.strong:
      return (
        bg: const Color(0xFFFFEDD5),
        border: const Color(0xFFF97316),
        fg: const Color(0xFF9A3412),
      );
    case UndeliveredAgingBand.critical:
      return (
        bg: Colors.red.shade50,
        border: Colors.red.shade300,
        fg: Colors.red.shade900,
      );
  }
}
