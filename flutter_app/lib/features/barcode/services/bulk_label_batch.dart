import 'barcode_pdf_service.dart';

class BulkLabelBatchResult {
  const BulkLabelBatchResult({
    required this.labels,
    this.failedIds = const [],
    this.failuresById = const {},
  });

  final List<BarcodeLabelData> labels;
  final List<String> failedIds;
  final Map<String, String> failuresById;

  bool get hasPartialFailure =>
      failedIds.isNotEmpty && labels.isNotEmpty;

  bool get isTotalFailure => labels.isEmpty && failedIds.isNotEmpty;
}
