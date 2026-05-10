import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/models/trade_purchase_models.dart';

void main() {
  test('fromJson maps line_total and line_landing_gross independently', () {
    final l = TradePurchaseLine.fromJson({
      'id': 'x',
      'item_name': 'Rice',
      'qty': 10,
      'unit': 'BAG',
      'landing_cost': '100',
      'line_total': '945',
      'line_landing_gross': '1000',
      'kg_per_unit': '50',
      'landing_cost_per_kg': '2',
    });
    expect(l.lineTotal, closeTo(945, 0.02));
    expect(l.lineLandingGross, closeTo(1000, 0.02));
    expect(l.landingGross, closeTo(1000, 0.02));
  });
}
