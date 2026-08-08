import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/barcode/presentation/barcode_scan_result_panel.dart';

void main() {
  testWidgets('found item shows Add to Purchase when allowed', (tester) async {
    var purchase = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeScanResultPanel(
            code: '123',
            item: {
              'id': 'i1',
              'name': 'Basmati Rice',
              'barcode': '123',
              'unit': 'bag',
              'current_stock': 10,
            },
            canStockEdit: true,
            canAddToPurchase: true,
            onAddToPurchase: () => purchase++,
          ),
        ),
      ),
    );

    expect(find.text('Add to Purchase'), findsOneWidget);
    await tester.tap(find.text('Add to Purchase'));
    await tester.pump();
    expect(purchase, 1);
  });

  testWidgets('hides purchase CTA when purchase not allowed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BarcodeScanResultPanel(
            code: '123',
            item: {
              'id': 'i1',
              'name': 'Basmati Rice',
              'barcode': '123',
              'current_stock': 10,
            },
            canStockEdit: true,
            canAddToPurchase: false,
            onAddToPurchase: () {},
          ),
        ),
      ),
    );

    expect(find.text('Add to Purchase'), findsNothing);
  });

  testWidgets('not found shows permission message when read-only', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: BarcodeScanResultPanel(
            code: '999',
            notFound: true,
            canStockEdit: false,
          ),
        ),
      ),
    );

    expect(find.textContaining('not linked'), findsOneWidget);
    expect(find.textContaining("doesn't have permission"), findsOneWidget);
    expect(find.text('Create new item'), findsNothing);
  });
}
