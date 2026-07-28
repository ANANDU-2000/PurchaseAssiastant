import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harisree_warehouse/core/design_system/hexa_responsive.dart';
import 'package:harisree_warehouse/core/design_system/widgets/app_form_layout.dart';
import 'package:harisree_warehouse/core/widgets/friendly_load_error.dart';
import 'package:harisree_warehouse/shared/widgets/desktop_page_shell.dart';

Widget _wrap(Size size, Widget child) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('AppFormRow stacks on phone (390) and rows on tablet+ (820)',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Size(390, 844),
        const AppFormRow(
          children: [
            SizedBox(key: Key('a'), height: 40, child: Text('A')),
            SizedBox(key: Key('b'), height: 40, child: Text('B')),
          ],
        ),
      ),
    );
    expect(
      find.descendant(
        of: find.byType(AppFormRow),
        matching: find.byType(Column),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AppFormRow),
        matching: find.byType(Row),
      ),
      findsNothing,
    );

    await tester.pumpWidget(
      _wrap(
        const Size(820, 1180),
        const AppFormRow(
          children: [
            SizedBox(key: Key('a'), height: 40, child: Text('A')),
            SizedBox(key: Key('b'), height: 40, child: Text('B')),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(
        of: find.byType(AppFormRow),
        matching: find.byType(Row),
      ),
      findsOneWidget,
    );

    // 16px gap between short fields on tablet+
    final row = tester.widget<Row>(
      find.descendant(
        of: find.byType(AppFormRow),
        matching: find.byType(Row),
      ),
    );
    expect(
      row.children.whereType<SizedBox>().any((s) => s.width == 16),
      isTrue,
    );
  });

  testWidgets('DesktopPageShell caps form width at 720 on 1440 desktop',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        const Size(1440, 900),
        const DesktopPageShell(
          child: ColoredBox(
            color: Colors.red,
            child: SizedBox.expand(child: Text('form')),
          ),
        ),
      ),
    );
    await tester.pump();

    final sized = tester.widgetList<SizedBox>(find.byType(SizedBox));
    final capped = sized.where((s) => s.width == HexaResponsive.maxFormWidth);
    expect(capped, isNotEmpty);
    expect(HexaResponsive.maxFormWidth, 720);
    expect(find.text('form'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DesktopPageShell bounds height when parent is unbounded',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Size(1280, 900),
        ListView(
          children: const [
            DesktopPageShell(
              child: SizedBox(
                height: 200,
                child: Text('shell-child'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.text('shell-child'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('single scroll owner: AppFormLayout does not nest dual scrolls',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Size(390, 844),
        AppFormLayout(
          scrollable: true,
          children: List.generate(
            8,
            (i) => SizedBox(height: 48, child: Text('field-$i')),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GroupedSectionErrorCard renders multi-section failure banner',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const Size(820, 1180),
        GroupedSectionErrorCard(
          message: 'Some sections failed',
          failedSections: const ['Purchases', 'Stock'],
          onRetryAll: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('Purchases'), findsWidgets);
    expect(find.textContaining('Stock'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
