import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/providers/stock_opening_providers.dart';
import 'package:harisree_warehouse/features/stock/presentation/opening_stock_setup_page.dart';
import 'package:harisree_warehouse/shared/widgets/hexa_empty_state.dart';

void main() {
  testWidgets('opening stock empty shows HexaEmptyState on phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openingStockSetupProvider.overrideWith(
            (ref) async => {
              'summary': {
                'pending_count': 0,
                'completed_count': 0,
                'total_count': 0,
              },
              'items': <Map<String, dynamic>>[],
              'total': 0,
              'page': 1,
              'per_page': 50,
            },
          ),
        ],
        child: const MaterialApp(home: OpeningStockSetupPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(HexaEmptyState), findsOneWidget);
    expect(find.text('No opening stock items'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(
      find.text('No opening stock items match filters.'),
      findsNothing,
    );
  });

  testWidgets('opening stock error shows the load error with retry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          openingStockSetupProvider.overrideWith(
            (ref) async => throw Exception('network'),
          ),
        ],
        child: const MaterialApp(home: OpeningStockSetupPage()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(OpeningStockSetupLoadError), findsOneWidget);
    expect(find.text('Could not load opening stock'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
