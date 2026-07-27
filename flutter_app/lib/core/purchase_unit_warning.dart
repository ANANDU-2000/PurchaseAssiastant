// Unit mismatch hint for purchase lines when catalog has bag/weight metadata.

/// Shown as a small banner when the line unit may not match how catalog prices are defined.
String? purchaseUnitMismatchWarning({
  required Map<String, dynamic>? catalogRow,
  required String unitText,
  bool compact = false,
}) {
  if (catalogRow == null) return null;
  final u = unitText.trim().toLowerCase();
  if (u.isEmpty) return null;
  final defUnit = (catalogRow['default_purchase_unit'] ?? catalogRow['default_unit'])
          ?.toString()
          .toLowerCase() ??
      '';
  final kgPerBag = (catalogRow['default_kg_per_bag'] as num?)?.toDouble();

  final looksLikeBag = u == 'bag' || u == 'bags' || u == 'b';
  final catalogKg = defUnit == 'kg' || defUnit.isEmpty;
  if (looksLikeBag && catalogKg && kgPerBag != null && kgPerBag > 0) {
    if (compact) {
      return 'Per-kg catalog: ~$kgPerBag kg/bag — align rate with $unitText or change unit.';
    }
    return 'This catalog item is usually costed per kg, but the unit is “$unitText”. '
        'If landing cost is per kg, multiply by this bag size (~$kgPerBag kg/bag) or change the unit.';
  }
  if (!looksLikeBag && (defUnit == 'bag' || defUnit == 'bags')) {
    if (compact) {
      return 'Catalog default is bag; check landing matches $unitText.';
    }
    return 'Catalog default is bag, but the unit is “$unitText”. Check that the landing cost matches how you are counting the line.';
  }
  return null;
}
