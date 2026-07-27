import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/services/item_export_service.dart';

void main() {
  test('buildItemStatementFilename uses ddMMMyyyy', () {
    final f = buildItemStatementFilename(
      itemName: 'Sugar 50KG',
      asOf: DateTime(2026, 5, 13),
    );
    expect(f, 'Sugar_50KG_Statement_13May2026.pdf');
  });
}

