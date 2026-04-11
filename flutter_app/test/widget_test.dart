import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hexa_purchase_assistant/features/analytics/presentation/analytics_page.dart';
import 'package:hexa_purchase_assistant/features/auth/presentation/login_page.dart';

void main() {
  testWidgets('Login screen renders sign-in', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('Analytics screen shows date range UI', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AnalyticsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Date range'), findsOneWidget);
  });
}
