// Stock quantity display helpers (primary unit + derived KG for bags/tins).

String stockDisplayPrimary(double qty, String unit) {
  final u = unit.trim().toLowerCase();
  final label = u == 'sack' ? 'bag' : (u.isEmpty ? '' : u);
  final q = _fmtQty(qty);
  if (label.isEmpty) return q;
  return '$q ${label.toUpperCase()}';
}

String? stockDisplaySecondary(
  double qty,
  String unit,
  double? kgPerBag,
  double? kgPerTin,
) {
  final u = unit.trim().toLowerCase();
  if (u == 'bag' || u == 'sack') {
    if (kgPerBag != null && kgPerBag > 0) {
      return '= ${_fmtQty(qty * kgPerBag)} KG';
    }
  } else if (u == 'tin') {
    if (kgPerTin != null && kgPerTin > 0) {
      return '= ${_fmtQty(qty * kgPerTin)} KG';
    }
  }
  return null;
}

String _fmtQty(double n) {
  if (n == n.roundToDouble()) {
    return n.round().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]},',
        );
  }
  return n.toStringAsFixed(3);
}
