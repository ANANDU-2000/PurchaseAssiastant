import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/calc_engine.dart';

/// Mirrors `backend/tests/test_trade_header_totals_parity.py`:
/// `test_header_percent_discount_applies_before_freight_and_commission`.
void main() {
  test('header discount + freight + percent commission grand total parity', () {
    const line = TradeCalcLine(
      qty: 2,
      landingCost: 2500,
      kgPerUnit: 50,
      landingCostPerKg: 50,
    );
    const basis = TradeCommissionLine(
      itemName: 'SUGAR 50KG',
      unit: 'bag',
      qty: 2,
      kgPerUnit: 50,
    );
    final totals = computeTradeTotals(
      const TradeCalcRequest(
        lines: [line],
        headerDiscountPercent: 10,
        freightAmount: 100,
        freightType: 'separate',
        commissionPercent: 10,
        commissionMode: 'percent',
        commissionBasisLines: [basis],
      ),
    );
    expect(totals.qtySum, 2.0);
    expect(totals.amountSum, 5050.0);
  });
}
