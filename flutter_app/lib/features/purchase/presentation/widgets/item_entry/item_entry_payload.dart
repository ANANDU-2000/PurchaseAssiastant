/// Pure helpers for assembling purchase line wire maps from item entry.
void applyTaxPercentToPurchaseLineMap(
  Map<String, dynamic> m, {
  required bool taxOn,
  required double? typedTaxPercent,
  required double? catalogTaxPercent,
}) {
  if (!taxOn) {
    m['tax_percent'] = 0.0;
    return;
  }
  if (typedTaxPercent != null && typedTaxPercent > 0) {
    m['tax_percent'] = typedTaxPercent;
  } else if (catalogTaxPercent != null && catalogTaxPercent > 0) {
    m['tax_percent'] = catalogTaxPercent;
  }
}
