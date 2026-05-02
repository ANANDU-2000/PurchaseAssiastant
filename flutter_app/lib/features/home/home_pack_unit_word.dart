/// Uppercase packaging label for KPI/breakdown lines (qty-aware plural).
/// `BOX` → `BOXES` (not `BOXS`); `BAG`/`TIN` → `BAGS`/`TINS`.
String homePackUnitWord(String unit, double qty) {
  final upper = unit.toUpperCase();
  final plural = qty != 1;
  if (!plural) return upper;
  if (upper == 'BOX') return 'BOXES';
  return '${upper}S';
}
