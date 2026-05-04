import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/json_coerce.dart';
import 'package:hexa_purchase_assistant/features/purchase/domain/purchase_draft.dart';

void main() {
  test('coerceToDouble parses string decimals', () {
    expect(coerceToDouble('50.000'), closeTo(50, 1e-9));
    expect(coerceToDouble('1,234.5'), closeTo(1234.5, 1e-9));
    expect(coerceToDouble(null), 0);
    expect(coerceToDouble(42), 42);
  });

  test('PurchaseLineDraft.fromLineMap accepts string qty and kg_per_unit', () {
    final line = PurchaseLineDraft.fromLineMap({
      'item_name': 'Test',
      'qty': '1',
      'unit': 'bag',
      'purchase_rate': '1300',
      'landing_cost': '1300',
      'weight_per_unit': '50.000',
      'kg_per_unit': '50.000',
      'landing_cost_per_kg': '26',
      'selling_rate': '1350',
      'selling_cost': '1350',
    });
    expect(line.qty, 1);
    expect(line.kgPerUnit, closeTo(50, 1e-6));
    expect(line.landingCostPerKg, closeTo(26, 1e-6));
    expect(line.sellingPrice, closeTo(1350, 1e-6));
  });
}
