import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/reports/stock/reports_stock_models.dart';
import 'package:harisree_warehouse/features/reports/stock/reports_stock_status.dart';
import 'package:harisree_warehouse/features/reports/widgets/reports_stock_intel_card.dart';

void main() {
  testWidgets('ReportsStockIntelCard shows stock qty prominently', (tester) async {
    const item = ReportsStockIntelItem(
      id: 'abc',
      name: 'SUGAR 50 KG',
      category: 'Rice',
      unit: 'bag',
      currentStock: 2500,
      used7d: 0,
      used30d: 20,
      idleDays: 3,
      status: ReportsStockMovementStatus.slow,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportsStockIntelCard(item: item),
        ),
      ),
    );

    expect(find.text('SUGAR 50 KG'), findsOneWidget);
    expect(find.text('2,500 BAG'), findsOneWidget);
    expect(find.text('Slow Moving'), findsOneWidget);
    expect(find.textContaining('30d'), findsOneWidget);
  });
}
