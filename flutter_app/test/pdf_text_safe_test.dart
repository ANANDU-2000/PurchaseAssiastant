import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/core/services/pdf_text_safe.dart';

void main() {
  test('safePdfText replaces unsupported glyphs', () {
    expect(
      safePdfText('03 May 2026 → 01 Jun 2026'),
      '03 May 2026 to 01 Jun 2026',
    );
    expect(safePdfText('Rs. 100 – 200'), 'Rs. 100 - 200');
    expect(safePdfText('Total ₹1,000'), 'Total Rs.1,000');
    expect(safePdfText('a · b · c'), 'a | b | c');
    expect(safePdfCell(null), pdfEmpty);
    expect(safePdfCell(''), pdfEmpty);
  });

  test('pdfPeriodRange uses ASCII hyphen', () {
    expect(pdfPeriodRange('3 May', '1 Jun'), '3 May - 1 Jun');
  });
}
