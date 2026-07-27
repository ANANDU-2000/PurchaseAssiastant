import 'stock_tracking_profile.dart';

/// Client-side guard (backend re-validates on save).
String? validatePurchaseLineUnitAgainstCatalog(
  Map<String, dynamic>? catalogRow,
  String lineUnit,
) {
  if (catalogRow == null || catalogRow.isEmpty) return null;
  final defaultUnit =
      (catalogRow['default_unit'] ?? catalogRow['stock_unit'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  final pkg = (catalogRow['package_type'] ?? '').toString().toUpperCase();

  String mode;
  if (pkg.contains('RETAIL') || (defaultUnit == 'piece' && _hasWeight(catalogRow))) {
    mode = StockTrackingMode.retailPacket;
  } else if (defaultUnit == 'bag' || pkg.contains('SACK')) {
    mode = StockTrackingMode.wholesaleBag;
  } else if (defaultUnit == 'kg' || pkg.contains('LOOSE')) {
    mode = StockTrackingMode.looseKg;
  } else if (defaultUnit == 'box') {
    mode = StockTrackingMode.box;
  } else if (defaultUnit == 'tin') {
    mode = StockTrackingMode.tin;
  } else {
    mode = StockTrackingMode.piece;
  }

  final lu = lineUnit.trim().toLowerCase();
  if (mode == StockTrackingMode.wholesaleBag) {
    if (lu == 'piece' || lu == 'pcs' || lu == 'packet' || lu == 'pkt') {
      return 'This item uses BAG tracking only. Use bag or kg.';
    }
  }
  if (mode == StockTrackingMode.retailPacket) {
    if (lu == 'bag' || lu == 'sack') {
      return 'This item uses PIECE tracking (retail packet). Use piece or kg, not bag.';
    }
  }
  if (mode == StockTrackingMode.looseKg) {
    if (lu == 'bag' || lu == 'sack' || lu == 'piece' || lu == 'pcs') {
      return 'This item is loose KG. Enter quantity in kg only.';
    }
  }
  if (mode == StockTrackingMode.box && lu != 'box' && lu.isNotEmpty) {
    return 'This item uses BOX tracking only.';
  }
  if (mode == StockTrackingMode.tin &&
      lu != 'tin' &&
      lu != 'kg' &&
      lu.isNotEmpty) {
    return 'This item uses TIN tracking only.';
  }
  return null;
}

/// Catalog saved as loose kg but name/weight imply wholesale bag — fix on item edit.
bool catalogItemMisconfiguredAsLooseKgWithBagWeight(
  Map<String, dynamic>? catalogRow,
) {
  if (catalogRow == null || catalogRow.isEmpty) return false;
  final defaultUnit =
      (catalogRow['default_unit'] ?? catalogRow['stock_unit'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
  if (defaultUnit != 'kg') return false;
  if (_hasWeight(catalogRow)) return true;
  final name = catalogRow['name']?.toString() ?? '';
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*KG\b', caseSensitive: false)
      .firstMatch(name);
  if (m == null) return false;
  final kg = double.tryParse(m.group(1) ?? '');
  if (kg == null) return false;
  return {25, 30, 40, 45, 50, 55}.contains(kg.round());
}

bool _hasWeight(Map<String, dynamic> row) {
  final w = row['default_kg_per_bag'] ?? row['package_size'];
  if (w == null) return false;
  final n = double.tryParse(w.toString());
  return n != null && n > 0;
}
