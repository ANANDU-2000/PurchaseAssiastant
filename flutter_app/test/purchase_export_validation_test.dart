import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/models/trade_purchase_models.dart';
import 'package:harisree_warehouse/core/services/purchase_export_service.dart';

void main() {
  test('validatePurchaseForExport rejects empty lines', () {
    final p = TradePurchase(
      id: 'id',
      humanId: 'PO-1',
      purchaseDate: DateTime(2026, 5, 25),
      paidAmount: 0,
      totalAmount: 0,
      storedStatus: 'draft',
      derivedStatus: 'draft',
      remaining: 0,
      discount: 0,
      commissionPercent: 0,
      freightType: 'separate',
      lines: const [],
    );
    final v = validatePurchaseForExport(p);
    expect(v.ok, isFalse);
    expect(v.message, contains('no line items'));
  });
}
