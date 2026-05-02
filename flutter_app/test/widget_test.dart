import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hexa_purchase_assistant/core/providers/prefs_provider.dart';
import 'package:hexa_purchase_assistant/core/widgets/friendly_load_error.dart';
import 'package:hexa_purchase_assistant/features/analytics/presentation/analytics_page.dart';
import 'package:hexa_purchase_assistant/features/auth/presentation/login_page.dart';

void main() {
  testWidgets('Login screen renders sign-in', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(
          home: LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign In'), findsWidgets);
  });

  testWidgets('Analytics screen shows date range UI',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const MaterialApp(
          home: AnalyticsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Summary'), findsOneWidget);
    expect(find.text('Analytics'), findsOneWidget);
    expect(find.text('Last 30 days'), findsWidgets);
  });

  /// Uses [ProviderContainer] instead of pumping [HexaApp]: splash schedules a long
  /// `restore()` timeout that leaves pending timers in widget tests.
  test('themeModeProvider defaults to light when prefs unset', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test('themeModeProvider is light when pref set', () async {
    SharedPreferences.setMockInitialValues({
      kThemeModeKey: 'light',
    });
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  testWidgets('FriendlyLoadError shows message, default subtitle, and Retry',
      (WidgetTester tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendlyLoadError(
            message: 'Could not load test data',
            onRetry: () => retried = true,
          ),
        ),
      ),
    );
    expect(find.text('Could not load test data'), findsOneWidget);
    expect(find.text(kFriendlyLoadNetworkSubtitle), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });

  testWidgets('FriendlyLoadError subtitle can be hidden with null',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FriendlyLoadError(
            message: 'Error only',
            subtitle: null,
            onRetry: () {},
          ),
        ),
      ),
    );
    expect(find.text('Error only'), findsOneWidget);
    expect(find.text(kFriendlyLoadNetworkSubtitle), findsNothing);
  });
}
