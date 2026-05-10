import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/units/resolved_item_unit_context.dart';

Map<String, dynamic> _row({
  required String name,
  required String sellingUnit,
  String defaultUnit = 'piece',
  double? packageSize,
  String? packageMeasurement,
  double confidence = 84,
}) {
  return {
    'name': name,
    'default_unit': defaultUnit,
    'unit_resolution': {
      'selling_unit': sellingUnit,
      'canonical_unit_type': sellingUnit,
      'stock_unit': sellingUnit == 'BAG' ? 'KG' : 'PCS',
      'package_type': sellingUnit,
      'package_size': packageSize,
      'package_measurement': packageMeasurement,
      'inferred_confidence': confidence,
    },
  };
}

void main() {
  test('RUCHI retail packs resolve to box labels and formulas', () {
    final ctx = resolveItemUnitContext(
      itemName: 'RUCHI 425 GM',
      currentLineUnit: 'piece',
      catalogRow: _row(
        name: 'RUCHI 425 GM',
        sellingUnit: 'BOX',
        packageSize: 425,
        packageMeasurement: 'GM',
      ),
    );

    expect(ctx.sellingUnit, 'box');
    expect(ctx.rateDimension, 'box');
    expect(ctx.quantityLabel, 'No. of boxes *');
    expect(ctx.purchaseRateFieldLabel, 'Purchase Rate (₹/box) *');
    expect(ctx.totalFormula, 'qty_boxes * purchase_rate_per_box');
  });

  test('SUNRICH and DALDA box packs stay box even if DB default unit is piece', () {
    for (final name in const ['SUNRICH 400GM BOX', 'DALDA 1LTR BOX']) {
      final ctx = resolveItemUnitContext(
        itemName: name,
        currentLineUnit: 'piece',
        catalogRow: _row(name: name, sellingUnit: 'BOX'),
      );
      expect(ctx.sellingUnit, 'box', reason: name);
      expect(ctx.sellingRateFieldLabel, 'Selling Rate (₹/box)', reason: name);
    }
  });

  test('JEERAKAM and SUGAR bulk kg names resolve to bag with kg stock', () {
    for (final entry in const {
      'JEERAKAM 30 KG': 30.0,
      'SUGAR 50 KG': 50.0,
    }.entries) {
      final ctx = resolveItemUnitContext(
        itemName: entry.key,
        currentLineUnit: 'kg',
        catalogRow: _row(
          name: entry.key,
          sellingUnit: 'BAG',
          defaultUnit: 'kg',
          packageSize: entry.value,
          packageMeasurement: 'KG',
          confidence: 96,
        ),
      );
      expect(ctx.sellingUnit, 'bag', reason: entry.key);
      expect(ctx.stockUnit, 'kg', reason: entry.key);
      expect(ctx.weightPerUnit, entry.value, reason: entry.key);
      expect(ctx.purchaseRateFieldLabel, 'Purchase Rate (₹/bag) *');
    }
  });
}
