import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:harisree_warehouse/features/catalog/presentation/batch_item_create_page.dart';
import 'package:harisree_warehouse/shared/widgets/hexa_empty_state.dart';

void main() {
  testWidgets('categories empty shows HexaEmptyState + Open catalog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: BatchItemCreateCategoriesEmpty(
              onOpenCatalog: () => context.go('/catalog'),
            ),
          ),
        ),
        GoRoute(
          path: '/catalog',
          builder: (_, __) => const Scaffold(body: Text('catalog-page')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(HexaEmptyState), findsOneWidget);
    expect(find.text('No categories yet'), findsOneWidget);
    expect(find.text('No categories — create in Catalog.'), findsNothing);
    expect(find.text('Open catalog'), findsOneWidget);

    await tester.tap(find.text('Open catalog'));
    await tester.pumpAndSettle();
    expect(find.text('catalog-page'), findsOneWidget);
  });

  testWidgets('subcategories empty shows HexaEmptyState + Open catalog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BatchItemCreateSubcategoriesEmpty(
            onOpenCatalog: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HexaEmptyState), findsOneWidget);
    expect(find.text('No subcategories in this category'), findsOneWidget);
    expect(find.text('No subcategories in this category.'), findsNothing);
    expect(find.text('Open catalog'), findsOneWidget);
  });
}
