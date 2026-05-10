import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/calc_engine.dart';

/// Mirrors backend `test_trade_header_totals_parity.py`:
/// `test_header_freight_skipped_when_line_has_delivered_only`.
void main() {
  test('line delivered suppresses header freight and header billty/delivered', () {
    const line = TradeCalcLine(
      qty: 2,
      landingCost: 2500,
      kgPerUnit: 50,
      landingCostPerKg: 50,
      deliveredRate: 25,
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
        freightAmount: 999,
        freightType: 'separate',
        billtyRate: 50,
        deliveredRate: 50,
        commissionBasisLines: [basis],
      ),
    );
    expect(totals.amountSum, 5025.0);
  });

  test('line money plus line freight rolls into total before discount', () {
    const line = TradeCalcLine(
      qty: 1,
      landingCost: 1000,
      freightType: 'separate',
      freightValue: 40,
    );
    final t = computeTradeTotals(
      const TradeCalcRequest(
        lines: [line],
        freightAmount: 60,
        freightType: 'separate',
      ),
    );
    expect(t.amountSum, 1040.0);
  });
}
