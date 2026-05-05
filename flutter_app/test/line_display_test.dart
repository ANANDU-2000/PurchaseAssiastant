import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/models/trade_purchase_models.dart';
import 'package:hexa_purchase_assistant/core/utils/line_display.dart';

void main() {
  test('formatLineQtyWeight: bag with kg per unit — bags first', () {
    expect(
      formatLineQtyWeight(qty: 100, unit: 'bag', kgPerUnit: 50),
      '100 bags • 5,000 kg',
    );
    expect(
      formatLineQtyWeight(qty: 1, unit: 'bag', kgPerUnit: 50),
      '1 bag • 50 kg',
    );
  });

  test('formatLineQtyWeight: sugar scenario 5000 bags × 50 kg', () {
    expect(
      formatLineQtyWeight(qty: 5000, unit: 'bag', kgPerUnit: 50),
      '5000 bags • 2,50,000 kg',
    );
  });

  test('formatLineQtyWeight: plain kg line', () {
    expect(
      formatLineQtyWeight(qty: 5000, unit: 'kg', kgPerUnit: null),
      '5,000 kg',
    );
  });

  test('formatLineQtyWeightFromTradeLine uses ledger weight', () {
    final l = TradePurchaseLine(
      id: '1',
      itemName: 'SUGAR 50 KG',
      qty: 100,
      unit: 'bag',
      landingCost: 0,
      kgPerUnit: 50,
      landingCostPerKg: 26,
    );
    expect(formatLineQtyWeightFromTradeLine(l), '100 bags • 5,000 kg');
  });
}
