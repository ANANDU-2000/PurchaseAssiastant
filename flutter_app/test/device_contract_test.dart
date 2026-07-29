import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:harisree_warehouse/core/design_system/hexa_responsive.dart';
import 'package:harisree_warehouse/core/design_system/widgets/app_form_layout.dart';
import 'package:harisree_warehouse/core/theme/hexa_colors.dart';
import 'package:harisree_warehouse/shared/widgets/desktop_page_shell.dart';

/// Device-contract regression from DESIGN.md / master board Phase 6.
void main() {
  test('DESIGN breakpoint tokens match code', () {
    expect(kTabletMin, 600);
    expect(kDesktopMin, 1024);
    expect(kUltraWideMin, 1600);
    expect(HexaResponsive.maxFormWidth, 720);
    expect(HexaResponsive.maxSheetWidth, 640);
    expect(HexaColors.brandPrimary, const Color(0xFF0E4F46));
    expect(HexaColors.brandGold, const Color(0xFFD4AF37));
    expect(HexaColors.brandBackground, const Color(0xFFF7F9F6));
  });

  testWidgets('phone 390: AppFormRow stacks; desktop shell caps form width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(390, 844)),
        child: MaterialApp(
          home: Scaffold(
            body: AppFormRow(
              children: [
                SizedBox(height: 40, child: Text('A')),
                SizedBox(height: 40, child: Text('B')),
              ],
            ),
          ),
        ),
      ),
    );
    expect(
      find.descendant(
          of: find.byType(AppFormRow), matching: find.byType(Column)),
      findsOneWidget,
    );

    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(1440, 900)),
        child: MaterialApp(
          home: Scaffold(
            body: DesktopPageShell(
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox.expand(child: Text('form')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('form'), findsOneWidget);
    final widths = tester
        .widgetList<SizedBox>(find.byType(SizedBox))
        .where((s) => s.width == HexaResponsive.maxFormWidth);
    expect(widths, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('820 tablet: AppFormRow is side-by-side', (tester) async {
    await tester.binding.setSurfaceSize(const Size(820, 1180));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(820, 1180)),
        child: MaterialApp(
          home: Scaffold(
            body: AppFormRow(
              children: [
                SizedBox(height: 40, child: Text('L')),
                SizedBox(height: 40, child: Text('R')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.descendant(of: find.byType(AppFormRow), matching: find.byType(Row)),
      findsOneWidget,
    );
  });
}
