import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/stock/presentation/widgets/stock_desktop_detail_pane.dart';

void main() {
  testWidgets('StockDesktopDetailPane empty selection at 1280px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: StockDesktopDetailPane(item: null),
          ),
        ),
      ),
    );

    expect(find.text('Select an item'), findsOneWidget);
  });

  testWidgets('StockDesktopDetailPane shows 2x2 stats and More at 1280px',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final item = <String, dynamic>{
      'id': 'item-1',
      'name': 'SUGAR 50 KG',
      'unit': 'BAG',
      'current_stock': 50,
      'physical_stock_qty': 20,
      'pending_delivery_qty': 52,
      'opening_stock': 10,
      'purchased_qty': 40,
    };

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 800,
              child: StockDesktopDetailPane(item: item),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('SUGAR 50 KG'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Physical'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Diff'), findsOneWidget);
    expect(find.text('Verify physical'), findsOneWidget);
    expect(find.text('New purchase'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);
  });
}
