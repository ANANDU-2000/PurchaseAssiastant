import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_row_actions.dart';

void main() {
  testWidgets('stock row tap shows compact warehouse actions', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return TextButton(
                  onPressed: () => showStockRowActions(
                    context: context,
                    ref: ref,
                    item: const {
                      'id': 'item-1',
                      'name': '916 RAVA 50KG',
                      'current_stock': 150,
                      'stock_unit': 'bag',
                    },
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('916 RAVA 50KG'), findsOneWidget);
    expect(find.text('Update physical stock'), findsOneWidget);
    expect(find.text('Add purchase quantity'), findsOneWidget);
    expect(find.text('View item activity'), findsOneWidget);
  });

  testWidgets('physical action opens update sheet after actions dialog closes',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                return TextButton(
                  onPressed: () => showStockRowActions(
                    context: context,
                    ref: ref,
                    item: const {
                      'id': 'item-1',
                      'name': 'SUNRICH 400GM BOX',
                      'current_stock': 110,
                      'physical_stock_qty': 105,
                      'stock_unit': 'box',
                    },
                  ),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Update physical stock'), findsOneWidget);

    await tester.tap(find.text('Update physical stock'));
    await tester.pumpAndSettle();

    // Result-chained: update sheet opened (actions tile gone; cancel close present).
    expect(find.text('Update physical stock'), findsNothing);
    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(find.text('SUNRICH 400GM BOX'), findsOneWidget);
  });
}
