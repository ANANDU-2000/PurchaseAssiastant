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
}
