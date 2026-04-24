import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/features/purchase/domain/purchase_draft.dart';
import 'package:hexa_purchase_assistant/features/purchase/state/purchase_draft_provider.dart';

void main() {
  test('totals: single line, no tax/discount, separate freight, commission 10%', () {
    final d = PurchaseDraft(
      purchaseDate: DateTime(2025, 1, 1),
      freightType: 'separate',
      freightAmount: 5,
      commissionPercent: 10,
      lines: const [
        PurchaseLineDraft(
          itemName: 'A',
          qty: 2,
          unit: 'kg',
          landingCost: 10,
        ),
      ],
    );
    final t = computePurchaseTotals(d);
    final b = strictFooterBreakdown(d);
    // lineMoney: 2*10=20; no header disc; +freight5 = 25; +comm 2 = 27
    expect(t.amountSum, closeTo(27, 0.001));
    expect(b.subtotalGross, 20.0);
    expect(b.commission, closeTo(2, 0.001));
    expect(b.freight, 5.0);
  });

  test('totals: line with 10% tax', () {
    final d = PurchaseDraft(
      purchaseDate: DateTime(2025, 1, 1),
      freightType: 'separate',
      lines: const [
        PurchaseLineDraft(
          itemName: 'A',
          qty: 1,
          unit: 'kg',
          landingCost: 100,
          taxPercent: 10,
        ),
      ],
    );
    final t = computePurchaseTotals(d);
    expect(t.amountSum, closeTo(110, 0.001));
  });

  test('totals: included freight adds 0 in invoice-style footer freight row', () {
    final d = PurchaseDraft(
      purchaseDate: DateTime(2025, 1, 1),
      freightType: 'included',
      freightAmount: 100,
      lines: const [
        PurchaseLineDraft(
          itemName: 'A',
          qty: 1,
          unit: 'kg',
          landingCost: 50,
        ),
      ],
    );
    final t = computePurchaseTotals(d);
    final b = strictFooterBreakdown(d);
    expect(t.amountSum, 50.0);
    expect(b.freight, 0.0);
  });

  test('totals: weight line (kg fields) + plain kg line in one draft', () {
    final d = PurchaseDraft(
      purchaseDate: DateTime(2025, 1, 1),
      freightType: 'separate',
      lines: const [
        PurchaseLineDraft(
          itemName: 'Rice',
          qty: 100,
          unit: 'bag',
          landingCost: 2100,
          kgPerUnit: 50,
          landingCostPerKg: 42,
        ),
        PurchaseLineDraft(
          itemName: 'Loose',
          qty: 10,
          unit: 'kg',
          landingCost: 80,
        ),
      ],
    );
    final t = computePurchaseTotals(d);
    // 210000 + 800 = 210800
    expect(t.amountSum, closeTo(210800, 0.5));
  });
}
