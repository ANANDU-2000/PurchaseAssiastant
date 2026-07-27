import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/design_system/hexa_desktop_layout.dart';

void main() {
  testWidgets('DesktopTwoColumnGrid uses two columns at 1280px', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: DesktopTwoColumnGrid(
              children: [
                Container(key: const Key('a'), height: 40, color: Colors.red),
                Container(key: const Key('b'), height: 40, color: Colors.blue),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('a')), findsOneWidget);
    expect(find.byKey(const Key('b')), findsOneWidget);
  });
}
