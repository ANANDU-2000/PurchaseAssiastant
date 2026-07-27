/// Uppercase packaging label for KPI/breakdown lines (qty-aware plural).
/// `BOX` → `BOXES` (not `BOXS`); `BAG`/`TIN` → `BAGS`/`TINS`.
String homePackUnitWord(String unit, double qty) {
  final upper = unit.toUpperCase();
  final plural = qty != 1;
  if (!plural) return upper;
  if (upper == 'BOX') return 'BOXES';
  return '${upper}S';
}

String _fmtPackQty(double q) =>
    q == q.roundToDouble() ? q.round().toString() : q.toStringAsFixed(1);

/// "`qty` `UNIT`" from API line unit (`box`, `BAG`, etc.) so we never show `BOXS`.
String homePackQtyWithDbUnit(double qty, String? rawUnit) {
  final u = (rawUnit ?? '').trim();
  if (u.isEmpty || u == '—') return '${_fmtPackQty(qty)} QTY';
  final up = u.toUpperCase();
  if (up == 'KG' || up == 'KGS') return '${_fmtPackQty(qty)} KG';
  for (final key in ['BOX', 'BAG', 'TIN']) {
    if (up == key || up.contains(key)) {
      return '${_fmtPackQty(qty)} ${homePackUnitWord(key, qty)}';
    }
  }
  if (up.contains('PIECE')) {
    return '${_fmtPackQty(qty)} ${qty == 1 ? 'PIECE' : 'PIECES'}';
  }
  return '${_fmtPackQty(qty)} ${homePackUnitWord(up, qty)}';
}
