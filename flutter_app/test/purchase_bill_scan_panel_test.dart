import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hexa_purchase_assistant/core/providers/suppliers_list_provider.dart';
import 'package:hexa_purchase_assistant/features/purchase/presentation/widgets/purchase_bill_scan_panel.dart';

Finder _fieldByLabel(String label) {
  return find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
    description: 'TextField(labelText: $label)',
  );
}

void main() {
  testWidgets('PurchaseBillScanPanel blocks Apply until confirmed', (tester) async {
    var applied = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          suppliersListProvider.overrideWith((ref) async {
            return [
              {'id': 's1', 'name': 'ABC'},
            ];
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PurchaseBillScanPanel(
              onApplyDraft: (_) => applied = true,
              compactHeading: true,
            ),
          ),
        ),
      ),
    );

    // Link supplier to directory by exact name match.
    await tester.enterText(_fieldByLabel('Supplier (from bill)'), 'ABC');
    await tester.pumpAndSettle();

    // Add one line and fill required fields.
    await tester.tap(find.text('Add blank line'));
    await tester.pumpAndSettle();

    await tester.enterText(_fieldByLabel('Item name'), 'SUGAR 50 KG');
    await tester.enterText(_fieldByLabel('Qty'), '100');
    await tester.enterText(_fieldByLabel('Unit'), 'bag');
    await tester.enterText(_fieldByLabel('P rate'), '56');
    await tester.pumpAndSettle();

    // Try apply without confirmation checkbox: should not call onApplyDraft.
    await tester.ensureVisible(find.text('Apply to purchase'));
    await tester.tap(find.text('Apply to purchase'));
    await tester.pumpAndSettle();
    expect(applied, isFalse);
    expect(
      find.textContaining('Cannot apply yet:'),
      findsOneWidget,
    );
    // Let snackbar go away so it doesn't block taps.
    await tester.pump(const Duration(seconds: 5));

    // Confirm and apply.
    await tester.ensureVisible(
      find.text('I confirm supplier + all item rows are correct'),
    );
    await tester.tap(find.text('I confirm supplier + all item rows are correct'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Apply to purchase'));
    await tester.tap(find.text('Apply to purchase'));
    await tester.pumpAndSettle();
    expect(applied, isTrue);
  });
}

