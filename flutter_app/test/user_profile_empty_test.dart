import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:harisree_warehouse/features/settings/presentation/user_profile_page.dart';
import 'package:harisree_warehouse/shared/widgets/hexa_empty_state.dart';

void main() {
  testWidgets('missing user shows HexaEmptyState + Back to users',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const UserProfilePage(userId: 'missing-user'),
        ),
        GoRoute(
          path: '/settings/users',
          builder: (_, __) => const Scaffold(body: Text('users-page')),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          businessUserProfileProvider('missing-user').overrideWith(
            (ref) async => const <String, dynamic>{},
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byType(HexaEmptyState), findsOneWidget);
    expect(find.text('User not found'), findsOneWidget);
    expect(find.text('Back to users'), findsOneWidget);
    expect(find.text('User not found.'), findsNothing);

    await tester.tap(find.text('Back to users'));
    await tester.pumpAndSettle();
    expect(find.text('users-page'), findsOneWidget);
  });
}
