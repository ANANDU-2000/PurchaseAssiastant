import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/barcode/services/barcode_pdf_service.dart';

void main() {
  group('BarcodeLabelData.finiteQty', () {
    test('drops non-finite values', () {
      expect(BarcodeLabelData.finiteQty(double.nan), isNull);
      expect(BarcodeLabelData.finiteQty(double.infinity), isNull);
      expect(BarcodeLabelData.finiteQty(12.5), 12.5);
    });
  });

  group('BarcodePdfService.pdfQtyDisplayString', () {
    test('formats integers without toInt on infinity', () {
      expect(BarcodePdfService.pdfQtyDisplayString(101.0), '101');
      expect(BarcodePdfService.pdfQtyDisplayString(double.infinity), isNull);
      expect(BarcodePdfService.pdfQtyDisplayString(null), isNull);
      expect(BarcodePdfService.pdfQtyDisplayString(0), isNull);
    });

    test('formats fractional qty', () {
      expect(BarcodePdfService.pdfQtyDisplayString(2.5), '2.5');
    });
  });
}
