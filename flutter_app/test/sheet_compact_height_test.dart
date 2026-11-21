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

  testWidgets(
      'phone compact sheet scrolls under keyboard without clipping top',
      (tester) async {
    const phone = Size(390, 844);
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: phone,
          viewInsets: EdgeInsets.only(bottom: 300),
        ),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ListView(
                  children: List.generate(
                    40,
                    (i) => ListTile(title: Text('Stock row $i')),
                  ),
                ),
                floatingActionButton: FilledButton(
                  onPressed: () {
                    showHexaBottomSheet<void>(
                      context: context,
                      compact: true,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Physical stock'),
                          const SizedBox(height: 8),
                          const TextField(
                            decoration: InputDecoration(
                              labelText: 'Qty',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('Variance: 0 KG'),
                          const SizedBox(height: 12),
                          const Text('Reason'),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: const [
                              Chip(label: Text('Physical count')),
                              Chip(label: Text('Sale')),
                              Chip(label: Text('Damage')),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text('Notes (optional)'),
                          const SizedBox(height: 8),
                          const TextField(
                            key: Key('notes_field'),
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () {},
                            child: const Text('SAVE SYSTEM STOCK'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('Open stock'),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open stock'));
    await tester.pumpAndSettle();

    expect(find.byType(HexaResponsiveSheetViewport), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(HexaResponsiveSheetViewport),
        matching: find.byWidgetPredicate(
          (w) => w is ListView && w.shrinkWrap,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text('Physical stock'), findsOneWidget);
    expect(find.text('SAVE SYSTEM STOCK'), findsOneWidget);

    final topLabel = tester.getRect(find.text('Physical stock'));
    expect(topLabel.top, greaterThanOrEqualTo(0));

    await tester.ensureVisible(find.byKey(const Key('notes_field')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notes_field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'phone compact short sheet hugs content (not adaptive max height blank)',
      (tester) async {
    const phone = Size(390, 844);
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: phone),
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
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Short action'),
                            SizedBox(height: 12),
                            Text('One line only'),
                          ],
                        ),
                      );
                    },
                    child: const Text('Open short'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open short'));
    await tester.pumpAndSettle();

    final viewport = find.byType(HexaResponsiveSheetViewport);
    expect(viewport, findsOneWidget);
    final hostH = tester.getSize(viewport).height;
    final adaptive = HexaResponsive.adaptiveSheetMaxHeight(
      tester.element(viewport),
    );
    // Must hug content — not expand to ~86% screen white blank.
    expect(hostH, lessThan(adaptive * 0.45));
    expect(hostH, lessThan(280));
    expect(find.text('Short action'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'phone compact:false host has no outer SCSV so Expanded list works under keyboard',
      (tester) async {
    const phone = Size(390, 844);
    await tester.binding.setSurfaceSize(phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: phone,
          viewInsets: EdgeInsets.only(bottom: 280),
        ),
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
                            const Text('Pick item'),
                            const TextField(
                              decoration: InputDecoration(
                                hintText: 'Type to search…',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                children: const [
                                  ListTile(title: Text('Alpha')),
                                  ListTile(title: Text('Beta')),
                                  ListTile(title: Text('Gamma')),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Open picker'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(find.byType(HexaResponsiveSheetViewport), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(HexaResponsiveSheetViewport),
        matching: find.byType(SingleChildScrollView),
      ),
      findsNothing,
    );
    expect(find.text('Pick item'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
