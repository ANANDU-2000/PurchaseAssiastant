import 'package:flutter_test/flutter_test.dart';

import 'package:harisree_warehouse/core/utils/unit_utils.dart';

void main() {
  test('formatStockQtyForUnit rounds bag whole numbers', () {
    expect(formatStockQtyForUnit('bag', 10), '10');
    expect(formatStockQtyForUnit('bag', 10.5), '11');
  });
}
