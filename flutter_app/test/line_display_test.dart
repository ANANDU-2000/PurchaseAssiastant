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

  test('unitCountsAsBagFamily: sack counts like bag', () {
    expect(unitCountsAsBagFamily('sack'), true);
    expect(unitCountsAsBagFamily('SACK'), true);
    expect(unitCountsAsBagFamily('bag'), true);
    expect(unitCountsAsBagFamily('BAGS'), true);
    expect(unitCountsAsBagFamily('kg'), false);
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
    expect(formatLineQtyWeightFromTradeLine(l), '5,000 KG • 100 BAGS');
  });

  test('purchaseHistoryPackSummary: bag shows count + kg', () {
    final p = TradePurchase(
      id: '1',
      humanId: 'PUR-1',
      purchaseDate: DateTime(2026, 5, 1),
      paidAmount: 0,
      totalAmount: 1,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 1,
      lines: [
        TradePurchaseLine(
          id: 'a',
          itemName: 'SUGAR 50KG',
          qty: 100,
          unit: 'bag',
          landingCost: 0,
          kgPerUnit: 50,
        ),
      ],
    );
    final s = purchaseHistoryPackSummary(p);
    expect(s.contains('100'), true);
    expect(s.contains('bag'), true);
    expect(s.toLowerCase().contains('kg'), true);
  });

  test('purchaseHistoryPackSummary: box has no kg', () {
    final p = TradePurchase(
      id: '1',
      humanId: 'PUR-1',
      purchaseDate: DateTime(2026, 5, 1),
      paidAmount: 0,
      totalAmount: 1,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 1,
      lines: [
        TradePurchaseLine(
          id: 'a',
          itemName: 'SUNRICH 400GM BOX',
          qty: 100,
          unit: 'box',
          landingCost: 0,
        ),
      ],
    );
    expect(purchaseHistoryPackSummary(p).toLowerCase().contains('kg'), false);
  });

  test('purchaseHistoryPackSummary: mixed bag + box', () {
    final p = TradePurchase(
      id: '1',
      humanId: 'PUR-1',
      purchaseDate: DateTime(2026, 5, 1),
      paidAmount: 0,
      totalAmount: 1,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 1,
      lines: [
        TradePurchaseLine(
          id: 'a',
          itemName: 'SUGAR',
          qty: 100,
          unit: 'bag',
          landingCost: 0,
          kgPerUnit: 50,
        ),
        TradePurchaseLine(
          id: 'b',
          itemName: 'SUNRICH',
          qty: 2,
          unit: 'box',
          landingCost: 0,
        ),
      ],
    );
    final s = purchaseHistoryPackSummary(p);
    expect(s.contains('•'), true);
    expect(s.toLowerCase().contains('box'), true);
    expect(s.toLowerCase().contains('bag'), true);
  });

  test('purchaseHistoryItemHeadline: multi line', () {
    final p = TradePurchase(
      id: '1',
      humanId: 'PUR-1',
      purchaseDate: DateTime(2026, 5, 1),
      paidAmount: 0,
      totalAmount: 1,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 1,
      lines: [
        TradePurchaseLine(
          id: 'a',
          itemName: 'A',
          qty: 1,
          unit: 'bag',
          landingCost: 0,
          kgPerUnit: 50,
        ),
        TradePurchaseLine(
          id: 'b',
          itemName: 'B',
          qty: 1,
          unit: 'box',
          landingCost: 0,
        ),
      ],
    );
    expect(purchaseHistoryItemHeadline(p), '2 items');
  });
}
