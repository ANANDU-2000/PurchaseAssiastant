import 'package:intl/intl.dart';

import '../calc_engine.dart';
import '../models/trade_purchase_models.dart';

String _qtyStr(double qty) {
  if (qty == qty.roundToDouble()) return qty.round().toString();
  return qty.toStringAsFixed(qty >= 100 ? 0 : 2);
}

String _kgStr(double kg) {
  if (kg <= 0) return '';
  final rounded = kg == kg.roundToDouble();
  return rounded
      ? '${NumberFormat('#,##,##0', 'en_IN').format(kg.round())} kg'
      : '${NumberFormat('#,##,##0.##', 'en_IN').format(kg)} kg';
}

/// Human-readable qty + weight for purchase lines: **bags/box/tin count first**, then total kg.
/// Use everywhere list/detail/history shows a line to avoid "5000 kg • 250000 kg" confusion.
String formatLineQtyWeight({
  required double qty,
  required String unit,
  double? kgPerUnit,
  double? totalWeightKg,
}) {
  final u = unit.trim().toLowerCase();
  final uDisp = unit.trim().isEmpty ? 'unit' : unit.trim();
  final isBag = u == 'bag' || u == 'sack';
  final isBox = u == 'box';
  final isTin = u == 'tin';

  double? totalKg;
  if (totalWeightKg != null && totalWeightKg > 1e-9) {
    totalKg = totalWeightKg;
  } else if ((isBag || isBox || isTin) &&
      kgPerUnit != null &&
      kgPerUnit > 1e-9) {
    totalKg = qty * kgPerUnit;
  } else if (u == 'kg' ||
      u == 'kgs' ||
      u == 'kilogram' ||
      u == 'kilograms' ||
      u == 'quintal' ||
      u == 'qtl') {
    totalKg = qty;
  }

  if (isBag && totalKg != null && totalKg > 1e-9) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'bag' : 'bags'} • ${_kgStr(totalKg)}';
  }
  if (isBag) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'bag' : 'bags'}';
  }
  if (u == 'sack' && totalKg != null && totalKg > 1e-9) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'sack' : 'sacks'} • ${_kgStr(totalKg)}';
  }
  if (u == 'sack') {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'sack' : 'sacks'}';
  }
  if (isBox && totalKg != null && totalKg > 1e-9) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'box' : 'boxes'} • ${_kgStr(totalKg)}';
  }
  if (isBox) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'box' : 'boxes'}';
  }
  if (isTin && totalKg != null && totalKg > 1e-9) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'tin' : 'tins'} • ${_kgStr(totalKg)}';
  }
  if (isTin) {
    return '${_qtyStr(qty)} ${_qtyStr(qty) == '1' ? 'tin' : 'tins'}';
  }
  if (totalKg != null && totalKg > 1e-9) {
    return _kgStr(totalKg);
  }
  return '${_qtyStr(qty)} $uDisp';
}

/// Uses [ledgerTradeLineWeightKg] for box/tin/kg-from-structure when [totalWeight] absent.
String formatLineQtyWeightFromTradeLine(TradePurchaseLine l) {
  final w = ledgerTradeLineWeightKg(
    itemName: l.itemName,
    unit: l.unit,
    qty: l.qty,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
    kgPerUnit: l.kgPerUnit,
    boxMode: l.boxMode,
    itemsPerBox: l.itemsPerBox,
    weightPerItem: l.weightPerItem,
    kgPerBox: l.kgPerBox,
    weightPerTin: l.weightPerTin,
  );
  return formatLineQtyWeight(
    qty: l.qty,
    unit: l.unit,
    kgPerUnit: l.kgPerUnit,
    totalWeightKg: (l.totalWeight != null && l.totalWeight! > 1e-9)
        ? l.totalWeight
        : (w > 1e-9 ? w : null),
  );
}

/// Bag/sack lines for KPI and history **bag** counts (sugar often uses `sack` without "bag" in the string).
bool unitCountsAsBagFamily(String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  return u.contains('bag') || u.contains('sack');
}
