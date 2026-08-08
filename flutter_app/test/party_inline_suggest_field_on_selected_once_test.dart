import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/purchase/presentation/widgets/party_inline_suggest_field.dart';
import 'package:harisree_warehouse/shared/widgets/inline_search_field.dart';

void main() {
  testWidgets('tapping a suggestion fires onSelected exactly once',
      (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    final picks = <InlineSearchItem>[];

    const items = [
      InlineSearchItem(id: '1', label: 'Basmati Rice'),
      InlineSearchItem(id: '2', label: 'Moong Dal'),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartyInlineSuggestField(
            controller: controller,
            focusNode: focus,
            items: items,
            hintText: 'Item',
            minQueryLength: 0,
            maxMatches: 20,
            suggestionsAsOverlay: false,
            onSelected: picks.add,
          ),
        ),
      ),
    );

    focus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Basmati Rice'), findsOneWidget);

    await tester.tap(find.text('Basmati Rice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(picks, hasLength(1));
    expect(picks.single.id, '1');
    expect(controller.text, 'Basmati Rice');

    controller.dispose();
    focus.dispose();
  });

  testWidgets('tapping add-row fires onAddRow exactly once', (tester) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    var addCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PartyInlineSuggestField(
            controller: controller,
            focusNode: focus,
            items: const [
              InlineSearchItem(id: '1', label: 'Basmati Rice'),
            ],
            hintText: 'Item',
            minQueryLength: 0,
            maxMatches: 20,
            suggestionsAsOverlay: false,
            showAddRow: true,
            addRowLabel: 'Add new item',
            onAddRow: () => addCount++,
          ),
        ),
      ),
    );

    focus.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Add new item'), findsOneWidget);

    await tester.tap(find.text('Add new item'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(addCount, 1);

    controller.dispose();
    focus.dispose();
  });
}
