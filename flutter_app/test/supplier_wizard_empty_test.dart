import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:harisree_warehouse/features/contacts/presentation/supplier_create_wizard_page.dart';
import 'package:harisree_warehouse/shared/widgets/hexa_empty_state.dart';

void main() {
  testWidgets('brokers empty shows HexaEmptyState + Create new broker',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var created = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SupplierWizardBrokersEmpty(
            onCreateBroker: () => created = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HexaEmptyState), findsOneWidget);
    expect(find.text('No brokers yet'), findsOneWidget);
    expect(find.text('No brokers yet — create one above.'), findsNothing);
    expect(find.text('Create new broker'), findsOneWidget);

    await tester.tap(find.text('Create new broker'));
    await tester.pump();
    expect(created, isTrue);
  });

  testWidgets('categories empty shows HexaEmptyState + Open catalog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, __) => Scaffold(
            body: SupplierWizardCategoriesEmpty(
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
    expect(find.text('No categories in catalog yet'), findsOneWidget);
    expect(
      find.text(
        'No categories in catalog yet. Add categories under Catalog, then return here.',
      ),
      findsNothing,
    );
    expect(find.text('Open catalog'), findsOneWidget);

    await tester.tap(find.text('Open catalog'));
    await tester.pumpAndSettle();
    expect(find.text('catalog-page'), findsOneWidget);
  });
}
