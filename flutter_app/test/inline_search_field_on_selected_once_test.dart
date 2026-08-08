import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/shared/widgets/inline_search_field.dart';

void main() {
  testWidgets(
      'tapping option fires onSelected once and unfocus does not re-fire',
      (tester) async {
    final picks = <InlineSearchItem>[];
    final focus = FocusNode();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineSearchField(
            focusNode: focus,
            placeholder: 'Search',
            items: const [
              InlineSearchItem(id: '1', label: 'Basmati Rice'),
              InlineSearchItem(id: '2', label: 'Moong Dal'),
            ],
            onSelected: picks.add,
          ),
        ),
      ),
    );

    focus.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Bas');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Basmati Rice'), findsWidgets);

    await tester.tap(find.text('Basmati Rice').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(picks, hasLength(1));
    expect(picks.single.id, '1');

    // Unfocus after commit must not exact-match re-pick.
    focus.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(picks, hasLength(1));

    focus.dispose();
  });
}
