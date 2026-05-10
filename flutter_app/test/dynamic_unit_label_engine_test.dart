import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/models/trade_purchase_models.dart';
import 'package:hexa_purchase_assistant/core/units/dynamic_unit_label_engine.dart' as unit_lbl;

TradePurchaseLine _line({
  required String unit,
  Map<String, dynamic>? rateContext,
  double? kgPerUnit,
  double? landingCostPerKg,
  double landingCost = 100,
}) {
  return TradePurchaseLine(
    id: 't',
    itemName: 'Item',
    qty: 2,
    unit: unit,
    landingCost: landingCost,
    kgPerUnit: kgPerUnit,
    landingCostPerKg: landingCostPerKg,
    rateContext: rateContext,
  );
}

void main() {
  test('rupeePerDimChipLabel uses pretty dim tokens', () {
    expect(unit_lbl.rupeePerDimChipLabel('kg'), '₹/kg');
    expect(unit_lbl.rupeePerDimChipLabel('bag'), '₹/bag');
    expect(unit_lbl.rupeePerDimChipLabel('box'), '₹/box');
    expect(unit_lbl.rupeePerDimChipLabel('tin'), '₹/tin');
  });

  test('purchaseRateSuffix follows rate_context when present', () {
    final bagKg = _line(
      unit: 'bag',
      rateContext: <String, dynamic>{
        'purchase_rate_dim': 'kg',
        'selling_rate_dim': 'kg',
        'qty_dim': 'bag',
        'weight_priced_gross': true,
        'line_unit': 'bag',
      },
      kgPerUnit: 50,
      landingCostPerKg: 40,
      landingCost: 2000,
    );
    expect(unit_lbl.purchaseRateSuffix(bagKg), 'kg');

    final forcedBox = _line(
      unit: 'kg',
      rateContext: <String, dynamic>{
        'purchase_rate_dim': 'box',
        'selling_rate_dim': 'box',
        'qty_dim': 'box',
      },
    );
    expect(unit_lbl.purchaseRateSuffix(forcedBox), 'box');
  });

  test('purchaseRateSuffix falls back from unit when no rate_context', () {
    expect(unit_lbl.purchaseRateSuffix(_line(unit: 'bag')), 'bag');
    expect(unit_lbl.purchaseRateSuffix(_line(unit: 'BOX')), 'box');
    expect(unit_lbl.purchaseRateSuffix(_line(unit: 'tin')), 'tin');
    expect(unit_lbl.purchaseRateSuffix(_line(unit: 'pcs')), 'pcs');
  });

  test('field labels include rupee and suffix', () {
    final tin = _line(unit: 'tin');
    expect(unit_lbl.purchaseRateFieldLabel(tin), 'Purchase Rate (₹/tin)');
    expect(unit_lbl.sellingRateFieldLabel(tin), 'Selling Rate (₹/tin)');
  });
}
