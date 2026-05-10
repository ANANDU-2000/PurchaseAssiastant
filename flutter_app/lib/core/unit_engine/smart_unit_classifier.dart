import 'package:flutter/foundation.dart';

import 'unit_rules_loader.dart';

/// Separates **selling unit** (BAG, BOX, TIN, …) from **package size** (50KG, 850GM, …).
@immutable
class UnitClassification {
  const UnitClassification({
    required this.sellingUnit,
    this.packageType,
    this.packageSize,
    this.packageMeasurement,
    this.stockUnit,
    this.conversionFactor = 1.0,
    this.confidence = 0.0,
    this.ruleId,
  });

  final String sellingUnit;
  final String? packageType;
  final double? packageSize;
  final String? packageMeasurement;
  final String? stockUnit;
  final double conversionFactor;
  final double confidence;
  final String? ruleId;

  Map<String, dynamic> toJson() => {
        'selling_unit': sellingUnit,
        'package_type': packageType,
        'package_size': packageSize,
        'package_measurement': packageMeasurement,
        'stock_unit': stockUnit,
        'conversion_factor': conversionFactor,
        'confidence': confidence,
        'rule_id': ruleId,
      };
}

class SmartUnitClassifier {
  SmartUnitClassifier._();

  static final RegExp _sizeKg = RegExp(r'(\d+)\s*KG', caseSensitive: false);
  static final RegExp _sizeGm = RegExp(r'(\d+)\s*GM', caseSensitive: false);
  static final RegExp _sizeLtr = RegExp(r'(\d+)\s*LTR', caseSensitive: false);
  static final RegExp _sizeMl = RegExp(r'(\d+)\s*ML', caseSensitive: false);

  /// [categoryName] — parent category or seed bucket name (e.g. `Rice`, `MAIDA ATTA SOOJI`).
  /// [brandDetected] — true when OCR / matcher found a brand token on the line.
  static Future<UnitClassification> classify(
    String itemName, {
    String? categoryName,
    bool brandDetected = false,
  }) async {
    final rules = await UnitRulesLoader.load();
    final upper = itemName.toUpperCase().trim();
    final cat = (categoryName ?? '').toUpperCase().trim();

    // Explicit loose.
    if (upper.contains('LOOSE')) {
      return const UnitClassification(
        sellingUnit: 'KG',
        packageType: 'LOOSE',
        stockUnit: 'KG',
        conversionFactor: 1,
        confidence: 92,
        ruleId: 'loose',
      );
    }

    final detection = rules['smart_detection_rules'] as List<dynamic>? ?? [];
    for (var i = 0; i < detection.length; i++) {
      final row = detection[i] as Map<String, dynamic>;
      final cond = row['condition'] as Map<String, dynamic>? ?? {};
      final result = row['result'] as Map<String, dynamic>? ?? {};
      if (!_matchCondition(upper, cat, brandDetected, cond)) continue;
      final built = _fromRuleResult(upper, result, 'smart_rule_$i');
      if (built != null) return built;
    }

    // Category defaults from JSON.
    final catRules = rules['category_rules'] as Map<String, dynamic>? ?? {};
    for (final e in catRules.entries) {
      if (!cat.contains(e.key) && cat != e.key) continue;
      final m = e.value as Map<String, dynamic>;
      final du = (m['default_unit'] as String?)?.toUpperCase();
      final pt = (m['package_type'] as String?)?.toUpperCase();
      if (du == null) continue;
      final parsed = _parsePackageSize(upper, du, pt);
      return UnitClassification(
        sellingUnit: du,
        packageType: pt ?? parsed.packageType,
        packageSize: parsed.size,
        packageMeasurement: parsed.measurement,
        stockUnit: parsed.stockUnit,
        conversionFactor: parsed.conversionFactor,
        confidence: 70,
        ruleId: 'category_${e.key}',
      );
    }

    // Heuristic fallback from name tokens.
    final parsed = _parsePackageSize(upper, 'KG', null);
    if (parsed.size != null && parsed.measurement == 'KG' && (upper.contains('RICE') || upper.contains('SUGAR'))) {
      return UnitClassification(
        sellingUnit: 'BAG',
        packageType: 'SACK',
        packageSize: parsed.size,
        packageMeasurement: 'KG',
        stockUnit: 'KG',
        conversionFactor: parsed.size!,
        confidence: 65,
        ruleId: 'fallback_bag_sack',
      );
    }

    return UnitClassification(
      sellingUnit: 'PCS',
      confidence: 40,
      ruleId: 'fallback_pcs',
    );
  }

  static bool _matchCondition(
    String upperName,
    String upperCategory,
    bool brandDetected,
    Map<String, dynamic> cond,
  ) {
    final any = (cond['contains_any'] as List<dynamic>?)?.map((e) => e.toString().toUpperCase()).toList() ?? [];
    if (any.isNotEmpty && !any.any(upperName.contains)) return false;

    final cats = (cond['category_any'] as List<dynamic>?)?.map((e) => e.toString().toUpperCase()).toList() ?? [];
    if (cats.isNotEmpty) {
      final ok = cats.any((c) => upperCategory.contains(c) || upperCategory == c);
      if (!ok) return false;
    }

    if (cond['brand_detected'] == true && !brandDetected) return false;
    return true;
  }

  static UnitClassification? _fromRuleResult(String upper, Map<String, dynamic> result, String ruleId) {
    final su = (result['selling_unit'] as String?)?.toUpperCase();
    if (su == null) return null;
    final parsed = _parsePackageSize(upper, su, (result['package_type'] as String?)?.toUpperCase());
    final cf = (result['conversion_factor'] as num?)?.toDouble() ??
        parsed.conversionFactor;
    final st = (result['stock_unit'] as String?)?.toUpperCase() ?? parsed.stockUnit;
    return UnitClassification(
      sellingUnit: su,
      packageType: (result['package_type'] as String?)?.toUpperCase() ?? parsed.packageType,
      packageSize: parsed.size,
      packageMeasurement: parsed.measurement,
      stockUnit: st,
      conversionFactor: cf,
      confidence: 85,
      ruleId: ruleId,
    );
  }

  static _ParsedSize _parsePackageSize(String upper, String sellingUnit, String? packageTypeHint) {
    double? size;
    String? meas;
    if (_sizeKg.hasMatch(upper)) {
      size = double.tryParse(_sizeKg.firstMatch(upper)!.group(1)!);
      meas = 'KG';
    } else if (_sizeGm.hasMatch(upper)) {
      size = double.tryParse(_sizeGm.firstMatch(upper)!.group(1)!);
      meas = 'GM';
    } else if (_sizeLtr.hasMatch(upper)) {
      size = double.tryParse(_sizeLtr.firstMatch(upper)!.group(1)!);
      meas = 'LTR';
    } else if (_sizeMl.hasMatch(upper)) {
      size = double.tryParse(_sizeMl.firstMatch(upper)!.group(1)!);
      meas = 'ML';
    }

    var stock = 'PCS';
    var conv = 1.0;
    var pt = packageTypeHint;
    if (sellingUnit == 'BAG' && size != null && meas == 'KG') {
      stock = 'KG';
      conv = size;
      pt ??= 'SACK';
    } else if (sellingUnit == 'TIN' && size != null && (meas == 'LTR' || meas == 'ML')) {
      stock = 'TIN';
      conv = 1;
      pt ??= 'TIN';
    } else if (sellingUnit == 'BOX' && size != null) {
      stock = 'PCS';
      conv = 1;
      pt ??= 'BOX';
    } else if (sellingUnit == 'KG') {
      stock = 'KG';
      conv = 1;
      pt ??= 'LOOSE';
    }

    return _ParsedSize(size: size, measurement: meas, stockUnit: stock, conversionFactor: conv, packageType: pt);
  }
}

class _ParsedSize {
  const _ParsedSize({
    required this.size,
    required this.measurement,
    required this.stockUnit,
    required this.conversionFactor,
    required this.packageType,
  });

  final double? size;
  final String? measurement;
  final String? stockUnit;
  final double conversionFactor;
  final String? packageType;
}
