import 'package:flutter_test/flutter_test.dart';
import 'package:hexa_purchase_assistant/core/errors/barcode_operation_errors.dart';
import 'package:hexa_purchase_assistant/features/barcode/services/barcode_pdf_service.dart';

void main() {
  test('barcodeMessageForUser maps BarcodeOperationException', () {
    final e = BarcodeOperationException(
      'PDF generation failed.',
      kind: BarcodeOperationKind.pdfGeneration,
    );
    expect(barcodeMessageForUser(e), 'PDF generation failed.');
  });

  test('fromApiMap accepts string decimals', () {
    final label = BarcodeLabelData.fromApiMap({
      'item_code': 'ITM1',
      'item_name': 'Rice',
      'current_stock': '12.5',
    });
    expect(label, isNotNull);
    expect(label!.currentStock, 12.5);
  });
}
