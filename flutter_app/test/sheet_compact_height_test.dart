import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/design_system/hexa_responsive.dart';
import 'package:harisree_warehouse/shared/widgets/search_picker_sheet.dart';

void main() {
  testWidgets('showHexaBottomSheet compact avoids DraggableScrollableSheet',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showHexaBottomSheet<void>(
                      context: context,
                      compact: true,
                      child: const Text('Compact sheet body'),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.text('Compact sheet body'), findsOneWidget);
  });

  testWidgets(
      'desktop stock update dialog shows fields (not blank zero-height)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1440, 900)),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showHexaBottomSheet<void>(
                        context: context,
                        compact: true,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Editing: 12 BAG'),
                            const SizedBox(height: 8),
                            const TextField(
                              decoration: InputDecoration(
                                labelText: 'Physical stock',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton(
                              onPressed: () {},
                              child: const Text('SAVE PHYSICAL STOCK'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Update'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Update'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Editing: 12 BAG'), findsOneWidget);
    expect(find.text('SAVE PHYSICAL STOCK'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(ListView),
      ),
    );
    expect(list.shrinkWrap, isTrue);

    final dialogSize = tester.getSize(find.byType(Dialog));
    expect(dialogSize.height, greaterThan(80));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'desktop compact:false sheet uses fixed height (Expanded lists work)',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1440, 900)),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showHexaBottomSheet<void>(
                        context: context,
                        compact: false,
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            const Text('Bulk archive items'),
                            Expanded(
                              child: ListView(
                                children: const [
                                  ListTile(title: Text('Item A')),
                                  ListTile(title: Text('Item B')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Archive'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Bulk archive items'), findsOneWidget);
    expect(find.text('Item A'), findsOneWidget);
    expect(find.text('Item B'), findsOneWidget);
    final dialogSize = tester.getSize(find.byType(Dialog));
    expect(dialogSize.height, greaterThan(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('search picker uses bounded height column', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () {
                    showSearchPickerSheet<String>(
                      context: context,
                      title: 'Pick item',
                      rows: const [
                        SearchPickerRow(value: 'a', title: 'Alpha'),
                        SearchPickerRow(value: 'b', title: 'Beta'),
                      ],
                    );
                  },
                  child: const Text('Pick'),
                ),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets(
      'phone reports filter sheet uses Hexa host not DraggableScrollableSheet',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showHexaBottomSheet<void>(
                        context: context,
                        compact: false,
                        padding: EdgeInsets.zero,
                        child: SizedBox(
                          height:
                              HexaResponsive.adaptiveSheetMaxHeight(context) *
                                  0.88,
                          child: const Column(
                            children: [
                              Text('Filters'),
                              Expanded(child: Center(child: Text('Units'))),
                            ],
                          ),
                        ),
                      );
                    },
                    child: const Text('Filters'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(find.text('Units'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
