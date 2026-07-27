import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/services/pdf_locale.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async {
    await ensurePdfLocalesInitialized();
  });

  test('en_IN currency format works after locale init', () {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
    expect(fmt.format(1234.5), contains('1'));
  });

  test('en_IN date format does not throw', () {
    final fmt = DateFormat('dd MMM yyyy', 'en_IN');
    expect(fmt.format(DateTime(2026, 5, 25)), isNotEmpty);
  });
}
