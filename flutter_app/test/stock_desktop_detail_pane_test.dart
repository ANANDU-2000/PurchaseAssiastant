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
}
