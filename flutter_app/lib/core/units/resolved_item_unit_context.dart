import '../utils/unit_classifier.dart';

/// Canonical unit context for item-entry UI.
///
/// This is display/hydration context only. Money totals still come from the
/// backend-aligned calculation engine and persisted trade line fields.
class ResolvedItemUnitContext {
  const ResolvedItemUnitContext({
    required this.sellingUnit,
    required this.stockUnit,
    required this.rateDimension,
    required this.packageType,
    required this.packageSize,
    required this.packageMeasurement,
    required this.quantityLabel,
    required this.rateLabel,
    required this.displayLabel,
    required this.totalFormula,
    required this.quantityMode,
    required this.unitConfidence,
    required this.source,
    this.weightPerUnit,
  });

  final String sellingUnit;
  final String stockUnit;
  final String rateDimension;
  final String packageType;
  final double? packageSize;
  final String? packageMeasurement;
  final String quantityLabel;
  final String rateLabel;
  final String displayLabel;
  final String totalFormula;
  final String quantityMode;
  final double unitConfidence;
  final String source;
  final double? weightPerUnit;

  bool get isBag => sellingUnit == 'bag';
  bool get isBox => sellingUnit == 'box';
  bool get isTin => sellingUnit == 'tin';
  bool get isKg => sellingUnit == 'kg';

  String get purchaseRateFieldLabel => 'Purchase Rate (₹/$rateDimension) *';
  String get sellingRateFieldLabel => 'Selling Rate (₹/$rateDimension)';
}

String normalizeUnitToken(Object? raw) {
  final s = raw?.toString().trim().toLowerCase() ?? '';
  switch (s) {
    case 'bags':
    case 'sack':
    case 'sacks':
      return 'bag';
    case 'boxes':
    case 'ctn':
    case 'carton':
      return 'box';
    case 'tins':
    case 'can':
    case 'cans':
    case 'jar':
    case 'jars':
      return 'tin';
    case 'kgs':
    case 'kilogram':
    case 'kilograms':
    case 'qtl':
    case 'quintal':
      return 'kg';
    case 'piece':
    case 'pieces':
    case 'pc':
    case 'pkt':
    case 'packet':
      return 'pcs';
    default:
      return s.isEmpty ? 'unit' : s;
  }
}

ResolvedItemUnitContext resolveItemUnitContext({
  required String itemName,
  required String currentLineUnit,
  Map<String, dynamic>? catalogRow,
  UnitClassification? fallbackClassification,
}) {
  final unitResolutionRaw = catalogRow?['unit_resolution'];
  final unitResolution = unitResolutionRaw is Map
      ? Map<String, dynamic>.from(unitResolutionRaw)
      : const <String, dynamic>{};
  final persistedSelling = normalizeUnitToken(
    unitResolution['selling_unit'] ??
        unitResolution['canonical_unit_type'] ??
        catalogRow?['selling_unit'],
  );
  final confidence = _toDouble(
        unitResolution['inferred_confidence'] ??
            unitResolution['confidence'] ??
            catalogRow?['unit_confidence'],
      ) ??
      0;
  if (persistedSelling != 'unit' && confidence >= 60) {
    final pkgSize = _toDouble(unitResolution['package_size'] ?? catalogRow?['package_size']);
    final pkgMeas = (unitResolution['package_measurement'] ??
            catalogRow?['package_measurement'])
        ?.toString()
        .trim()
        .toUpperCase();
    return _contextFor(
      sellingUnit: persistedSelling,
      stockUnit: normalizeUnitToken(
        unitResolution['stock_unit'] ?? catalogRow?['stock_unit'],
      ),
      packageType: normalizeUnitToken(
        unitResolution['package_type'] ?? catalogRow?['package_type'],
      ),
      packageSize: pkgSize,
      packageMeasurement: pkgMeas?.isEmpty == true ? null : pkgMeas,
      unitConfidence: confidence,
      source: 'catalog_unit_resolution',
    );
  }

  final rowDefault = normalizeUnitToken(catalogRow?['default_purchase_unit'] ?? catalogRow?['default_unit']);
  final name = itemName.trim().toUpperCase();
  final classification = fallbackClassification ??
      UnitClassifier.classify(
        itemName: itemName,
        lineUnit: currentLineUnit,
        catalogDefaultUnit: catalogRow?['default_unit']?.toString(),
        catalogDefaultKgPerBag: _toDouble(catalogRow?['default_kg_per_bag']),
        categoryName: catalogRow?['category_name']?.toString() ??
            catalogRow?['category']?.toString(),
        subcategoryName: catalogRow?['subcategory_name']?.toString() ??
            catalogRow?['subcategory']?.toString(),
      );

  if (classification.type == UnitType.weightBag) {
    return _contextFor(
      sellingUnit: 'bag',
      stockUnit: 'kg',
      packageType: 'bag',
      packageSize: classification.kgFromName ?? _toDouble(catalogRow?['default_kg_per_bag']),
      packageMeasurement: 'KG',
      unitConfidence: 75,
      source: 'flutter_classifier',
    );
  }
  if (name.contains('BOX') || name.contains('CTN') || name.contains('CARTON')) {
    return _contextFor(
      sellingUnit: 'box',
      stockUnit: 'pcs',
      packageType: 'box',
      packageSize: _packageSizeFromName(name).$1,
      packageMeasurement: _packageSizeFromName(name).$2,
      unitConfidence: 75,
      source: 'flutter_name_box',
    );
  }
  if (name.contains('TIN') || name.contains('CAN') || name.contains('JAR')) {
    return _contextFor(
      sellingUnit: 'tin',
      stockUnit: 'pcs',
      packageType: 'tin',
      packageSize: _packageSizeFromName(name).$1,
      packageMeasurement: _packageSizeFromName(name).$2,
      unitConfidence: 75,
      source: 'flutter_name_tin',
    );
  }
  if (rowDefault == 'pcs') {
    final size = _packageSizeFromName(name);
    if (size.$1 != null && {'GM', 'ML', 'LTR'}.contains(size.$2)) {
      return _contextFor(
        sellingUnit: 'box',
        stockUnit: 'pcs',
        packageType: 'box',
        packageSize: size.$1,
        packageMeasurement: size.$2,
        unitConfidence: 68,
        source: 'flutter_retail_pack',
      );
    }
  }
  return _contextFor(
    sellingUnit: rowDefault == 'unit' ? normalizeUnitToken(currentLineUnit) : rowDefault,
    stockUnit: rowDefault == 'kg' ? 'kg' : 'pcs',
    packageType: rowDefault,
    packageSize: _packageSizeFromName(name).$1,
    packageMeasurement: _packageSizeFromName(name).$2,
    unitConfidence: 50,
    source: 'legacy_fallback',
  );
}

ResolvedItemUnitContext _contextFor({
  required String sellingUnit,
  required String stockUnit,
  required String packageType,
  required double? packageSize,
  required String? packageMeasurement,
  required double unitConfidence,
  required String source,
}) {
  final selling = normalizeUnitToken(sellingUnit);
  final stock = normalizeUnitToken(stockUnit);
  final rate = switch (selling) {
    'bag' => 'bag',
    'box' => 'box',
    'tin' => 'tin',
    'pcs' => 'pcs',
    'kg' => 'kg',
    _ => selling,
  };
  final qtyLabel = switch (selling) {
    'bag' => 'No. of bags *',
    'box' => 'No. of boxes *',
    'tin' => 'No. of tins *',
    'kg' => 'Qty (kg) *',
    'pcs' => 'Qty (pcs) *',
    _ => 'Qty *',
  };
  final formula = switch (selling) {
    'bag' => 'qty_bags * purchase_rate_per_bag',
    'box' => 'qty_boxes * purchase_rate_per_box',
    'tin' => 'qty_tins * purchase_rate_per_tin',
    'kg' => 'qty_kg * purchase_rate_per_kg',
    'pcs' => 'qty_pcs * purchase_rate_per_pcs',
    _ => 'qty * purchase_rate',
  };
  return ResolvedItemUnitContext(
    sellingUnit: selling,
    stockUnit: stock,
    rateDimension: rate,
    packageType: normalizeUnitToken(packageType),
    packageSize: packageSize,
    packageMeasurement: packageMeasurement,
    quantityLabel: qtyLabel,
    rateLabel: '₹/$rate',
    displayLabel: selling.toUpperCase(),
    totalFormula: formula,
    quantityMode: rate,
    unitConfidence: unitConfidence,
    source: source,
    weightPerUnit: selling == 'bag' && packageMeasurement == 'KG' ? packageSize : null,
  );
}

double? _toDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

(double?, String?) _packageSizeFromName(String upperName) {
  final match = RegExp(r'(\d+(?:\.\d+)?)\s*(KG|GM|G|ML|LTR|LITRE|LITER|L)\b')
      .firstMatch(upperName);
  if (match == null) return (null, null);
  final size = double.tryParse(match.group(1) ?? '');
  var measure = match.group(2)?.toUpperCase();
  if (measure == 'G') measure = 'GM';
  if (measure == 'L' || measure == 'LITRE' || measure == 'LITER') {
    measure = 'LTR';
  }
  return (size, measure);
}
