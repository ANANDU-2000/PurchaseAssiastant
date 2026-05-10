import 'smart_unit_classifier.dart';

class LineValidationIssue {
  const LineValidationIssue(this.code, this.message);
  final String code;
  final String message;
}

/// Lightweight client-side checks; backend must re-validate all money fields.
class SmartValidationEngine {
  SmartValidationEngine._();

  static List<LineValidationIssue> validateLine({
    required double qty,
    required double purchaseRate,
    double? sellingRate,
    UnitClassification? classification,
  }) {
    final out = <LineValidationIssue>[];
    if (qty <= 0) {
      out.add(const LineValidationIssue('qty', 'Quantity must be positive.'));
    }
    if (purchaseRate < 0) {
      out.add(const LineValidationIssue('purchase_rate', 'Purchase rate cannot be negative.'));
    }
    if (sellingRate != null && sellingRate < 0) {
      out.add(const LineValidationIssue('selling_rate', 'Selling rate cannot be negative.'));
    }
    if (classification != null && classification.confidence < 50) {
      out.add(LineValidationIssue(
        'low_confidence',
        'Low unit confidence (${classification.confidence.toStringAsFixed(0)}). Review selling unit vs package size.',
      ));
    }
    return out;
  }
}
