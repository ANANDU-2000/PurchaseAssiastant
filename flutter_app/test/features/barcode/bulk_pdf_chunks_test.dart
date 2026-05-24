import 'package:flutter_test/flutter_test.dart';
import 'package:harisree_warehouse/features/barcode/services/barcode_pdf_service.dart';
import 'package:harisree_warehouse/features/barcode/services/bulk_pdf_chunks.dart';

BarcodeLabelData _label(String code) => BarcodeLabelData(
      itemCode: code,
      itemName: code,
      barcode: code,
    );

void main() {
  test('chunkExpandedLabelsForPdfFiles splits 95 labels into 40+40+15', () {
    final items = List.generate(95, (i) => _label('I$i'));
    final chunks = chunkExpandedLabelsForPdfFiles(
      items: items,
      copiesPerItem: 1,
      perFile: 40,
    );
    expect(chunks.length, 3);
    expect(chunks[0].length, 40);
    expect(chunks[1].length, 40);
    expect(chunks[2].length, 15);
  });

  test('copies expand before chunking', () {
    final items = [_label('A'), _label('B')];
    final chunks = chunkExpandedLabelsForPdfFiles(
      items: items,
      copiesPerItem: 2,
      perFile: 3,
    );
    expect(chunks.length, 2);
    expect(chunks[0].length, 3);
    expect(chunks[1].length, 1);
  });
}
