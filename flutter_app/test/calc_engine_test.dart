import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/calc_engine.dart';

void main() {
  test('lineMoney plain', () {
    final m = lineMoney(const TradeCalcLine(
      qty: 10,
      landingCost: 100,
      taxPercent: 0,
    ));
    expect(m, 1000.0);
  });

  test('lineMoney with tax', () {
    final m = lineMoney(const TradeCalcLine(
      qty: 10,
      landingCost: 100,
      taxPercent: 5,
    ));
    expect(m, 1050.0);
  });

  test('lineMoney with line discount', () {
    final m = lineMoney(const TradeCalcLine(
      qty: 10,
      landingCost: 100,
      discountPercent: 10,
      taxPercent: 0,
    ));
    expect(m, 900.0);
  });

  test('lineMoney kg_per_unit + landing_cost_per_kg matches per-bag rate', () {
    const perBag = 2100.0;
    const qty = 100.0;
    const kpu = 50.0;
    const perKg = 42.0;
    final kg = lineMoney(const TradeCalcLine(
      qty: qty,
      landingCost: perBag,
      kgPerUnit: kpu,
      landingCostPerKg: perKg,
      taxPercent: 0,
    ));
    final bag = lineMoney(const TradeCalcLine(
      qty: qty,
      landingCost: perBag,
      taxPercent: 0,
    ));
    expect(kg, bag);
  });

  test('computeTradeTotals header discount and commission', () {
    final t = computeTradeTotals(const TradeCalcRequest(
      headerDiscountPercent: 10,
      commissionPercent: 5,
      lines: [
        TradeCalcLine(
          qty: 10,
          landingCost: 100,
          taxPercent: 0,
        ),
      ],
    ));
    expect(t.qtySum, 10.0);
    const afterHeader = 900.0;
    expect(t.amountSum, closeTo(afterHeader + afterHeader * 0.05, 1e-9));
  });

  test('parity: one BAG @ 2250 + 2% commission (matches Python compute_totals)', () {
    const afterHeader = 2250.0;
    final t = computeTradeTotals(const TradeCalcRequest(
      commissionPercent: 2,
      lines: [
        TradeCalcLine(
          qty: 1,
          landingCost: 2250,
          taxPercent: 0,
        ),
      ],
    ));
    expect(t.qtySum, 1.0);
    expect(t.amountSum, closeTo(afterHeader + afterHeader * 0.02, 1e-9));
  });

  test('computeTradeTotals freight separate vs included', () {
    const line = TradeCalcLine(
      qty: 1,
      landingCost: 100,
      taxPercent: 0,
    );
    final sep = computeTradeTotals(const TradeCalcRequest(
      freightAmount: 50,
      freightType: 'separate',
      lines: [line],
    ));
    final inc = computeTradeTotals(const TradeCalcRequest(
      freightAmount: 50,
      freightType: 'included',
      lines: [line],
    ));
    expect(sep.amountSum, 150.0);
    expect(inc.amountSum, 100.0);
  });
}
