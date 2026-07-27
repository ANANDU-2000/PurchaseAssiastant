import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:harisree_warehouse/core/router/navigation_ext.dart';

void main() {
  testWidgets('popImperativeOrGo uses fallbackGo when stack is empty', (tester) async {
    late String location;

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/target',
          routes: [
            GoRoute(
              path: '/target',
              builder: (context, _) {
                return Scaffold(
                  body: TextButton(
                    onPressed: () => popImperativeOrGo(
                      context,
                      fallbackGo: '/purchase',
                    ),
                    child: const Text('pop'),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/purchase',
              builder: (context, state) =>
                  const Scaffold(body: Text('purchase list')),
            ),
          ],
          redirect: (context, state) {
            location = state.uri.path;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('pop'));
    await tester.pumpAndSettle();

    expect(find.text('purchase list'), findsOneWidget);
    expect(location, '/purchase');
  });
}
