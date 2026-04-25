import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/calc_engine.dart';
import 'package:hexa_purchase_assistant/core/models/trade_purchase_models.dart';
import 'package:hexa_purchase_assistant/core/services/purchase_invoice_pdf_layout.dart';

void main() {
  test('tradeCalcRequestFromTradePurchase matches sample total (no billty)', () {
    final p = TradePurchase(
      id: 'a',
      humanId: 'PUR-2026-1',
      purchaseDate: DateTime(2026, 4, 1),
      paidAmount: 0,
      totalAmount: 110.0,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 110,
      discount: 0,
      commissionPercent: 0,
      freightType: 'separate',
      lines: [
        TradePurchaseLine(
          id: '1',
          itemName: 'A',
          qty: 1,
          unit: 'kg',
          landingCost: 100,
          taxPercent: 10,
        ),
      ],
    );
    final t = computeTradeTotals(tradeCalcRequestFromTradePurchase(p));
    expect(t.amountSum, closeTo(110, 0.001));
    expect(t.amountSum, closeTo(p.totalAmount, 0.02));
  });

  test('billty and delivered are included in total', () {
    final line = TradePurchaseLine(
      id: '1',
      itemName: 'A',
      qty: 1,
      unit: 'kg',
      landingCost: 100,
    );
    final p = TradePurchase(
      id: 'a',
      humanId: 'PUR-1',
      purchaseDate: DateTime(2026, 4, 1),
      paidAmount: 0,
      totalAmount: 115.0,
      storedStatus: 'confirmed',
      derivedStatus: 'confirmed',
      remaining: 115,
      billtyRate: 10,
      deliveredRate: 5,
      freightType: 'separate',
      lines: [line],
    );
    final t = computeTradeTotals(tradeCalcRequestFromTradePurchase(p));
    expect(t.amountSum, closeTo(115, 0.001));
  });

  test('lineTaxableAfterLineDisc + lineTaxAmount equals lineMoney (with tax)', () {
    const c = TradeCalcLine(
      qty: 1,
      landingCost: 100,
      taxPercent: 10,
    );
    final tax = lineTaxAmount(c);
    final base = lineTaxableAfterLineDisc(c);
    expect(lineMoney(c), closeTo(base + tax, 1e-9));
  });
}
