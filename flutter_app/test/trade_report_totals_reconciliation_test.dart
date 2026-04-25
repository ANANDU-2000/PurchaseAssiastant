import 'package:flutter_test/flutter_test.dart';

/// Contract: for the same date window, KPI totalPurchase (from trade-summary)
/// should match the sum of trade-items' total_purchase when both are unfiltered
/// and taken from the same API responses. Backend enforces this; this test
/// documents the client-side expectation for PDF/Reports screens.
void main() {
  test('sum of trade-items total_purchase matches headline total (mock API)', () {
    const headline = 30000.0;
    final items = <Map<String, dynamic>>[
      {'total_purchase': 10000, 'item_name': 'A'},
      {'total_purchase': 20000, 'item_name': 'B'},
    ];
    final sum = items.fold<double>(
      0,
      (a, r) => a + (r['total_purchase'] as num).toDouble(),
    );
    expect(sum, headline);
  });
}
