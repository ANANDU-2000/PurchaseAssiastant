import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:harisree_warehouse/features/catalog/presentation/catalog_item_create_page.dart';
import 'package:harisree_warehouse/shared/widgets/hexa_empty_state.dart';

void main() {
  testWidgets('suppliers empty shows HexaEmptyState + Open Contacts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: CatalogItemCreateSuppliersEmpty(
              onOpenContacts: () => context.go('/contacts'),
            ),
          ),
        ),
        GoRoute(
          path: '/contacts',
          builder: (_, __) => const Scaffold(body: Text('contacts-page')),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(HexaEmptyState), findsOneWidget);
    expect(find.text('No suppliers yet'), findsOneWidget);
    expect(find.text('No suppliers yet — add in Contacts.'), findsNothing);
    expect(find.text('Open Contacts'), findsOneWidget);

    await tester.tap(find.text('Open Contacts'));
    await tester.pumpAndSettle();
    expect(find.text('contacts-page'), findsOneWidget);
  });

  testWidgets('subcategories empty shows HexaEmptyState + Open catalog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: CatalogItemCreateSubcategoriesEmpty(
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
    expect(find.text('No subcategories yet'), findsOneWidget);
    expect(find.text('No subcategories — add in Catalog first.'), findsNothing);
    expect(find.text('Open catalog'), findsOneWidget);

    await tester.tap(find.text('Open catalog'));
    await tester.pumpAndSettle();
    expect(find.text('catalog-page'), findsOneWidget);
  });
}
