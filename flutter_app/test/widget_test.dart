import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hexa_purchase_assistant/core/providers/prefs_provider.dart';
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
    expect(find.text('Sign in'), findsWidgets);
  });

  testWidgets('Analytics screen shows date range UI', (WidgetTester tester) async {
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
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Date range'), findsOneWidget);
  });
}
