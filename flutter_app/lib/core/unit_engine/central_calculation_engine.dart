import 'dart:math' as math;

/// Server-side totals remain authoritative; this mirrors **line math** for UI preview.
class CentralCalculationEngine {
  CentralCalculationEngine._();

  static double purchaseTotal({required double qty, required double purchaseRate}) {
    return _roundMoney(qty * purchaseRate);
  }

  static double sellingTotal({required double qty, required double sellingRate}) {
    return _roundMoney(qty * sellingRate);
  }

  static double profit({
    required double qty,
    required double purchaseRate,
    required double sellingRate,
  }) {
    return _roundMoney(sellingTotal(qty: qty, sellingRate: sellingRate) -
        purchaseTotal(qty: qty, purchaseRate: purchaseRate));
  }

  /// `qty` in selling units × `conversionFactor` to base weight (e.g. BAG × kg per bag).
  static double totalWeightKg({
    required double qty,
    required double conversionFactorToKg,
  }) {
    if (conversionFactorToKg <= 0) return 0;
    return _roundWeight(qty * conversionFactorToKg);
  }

  static double _roundMoney(double v) => (v * 100).round() / 100.0;

  static double _roundWeight(double v) => (v * 1000).round() / 1000.0;

  static double gmToKg(double gm) => gm / 1000.0;

  static double safeQty(num? q) {
    if (q == null) return 0;
    final d = q.toDouble();
    if (d.isNaN || !d.isFinite) return 0;
    return math.max(0, d);
  }
}
