import 'package:flutter_test/flutter_test.dart';

import 'package:harisree_warehouse/features/barcode/presentation/warehouse_scan_action_sheet.dart';

void main() {
  test('formatQty rounds whole numbers', () {
    expect(formatQty(10), '10');
    expect(formatQty(10.5), '10.5');
  });
}
