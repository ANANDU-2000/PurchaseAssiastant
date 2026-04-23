// Parsing FastAPI / Starlette error bodies: { "detail": "..." } or
// { "detail": [ { "loc": [...], "msg": "..." }, ... ] }.

/// Human-readable text from a JSON error body, or null if none.
String? fastApiDetailString(Object? data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is String) {
    final t = detail.trim();
    return t.isEmpty ? null : t;
  }
  if (detail is List) {
    final parts = <String>[];
    for (final e in detail) {
      if (e is! Map) continue;
      final msg = e['msg']?.toString();
      if (msg == null) continue;
      final loc = e['loc'];
      if (loc is List) {
        final segs = <String>[];
        for (final x in loc) {
          if (x == 'body') continue;
          segs.add(x.toString());
        }
        if (segs.isNotEmpty) {
          parts.add('${segs.join('.')}: $msg');
        } else {
          parts.add(msg);
        }
      } else {
        parts.add(msg);
      }
    }
    if (parts.isEmpty) return null;
    const maxLines = 6;
    if (parts.length <= maxLines) return parts.join('\n');
    return '${parts.take(maxLines).join('\n')}\n…';
  }
  return null;
}

/// Hints for scrolling the purchase wizard to the relevant field on validation errors.
class FastApiPurchaseScrollHint {
  const FastApiPurchaseScrollHint._({this.supplierField = false, this.lineIndex});

  const FastApiPurchaseScrollHint.supplier() : this._(supplierField: true);

  /// 0-based line index from e.g. `["body", "lines", 2, "qty"]`.
  const FastApiPurchaseScrollHint.line(int index) : this._(supplierField: false, lineIndex: index);

  final bool supplierField;
  final int? lineIndex;
}

/// Best-effort parse of `lines[i]` / `supplier_id` from a 422 [detail] list.
FastApiPurchaseScrollHint? fastApiPurchaseScrollHint(Object? data) {
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! List) return null;
  for (final e in detail) {
    if (e is! Map) continue;
    final loc = e['loc'];
    if (loc is! List) continue;
    final segs = <String>[];
    for (final x in loc) {
      if (x == 'body') continue;
      segs.add(x.toString());
    }
    if (segs.isNotEmpty && segs.last == 'supplier_id') {
      return const FastApiPurchaseScrollHint.supplier();
    }
    final li = segs.indexOf('lines');
    if (li >= 0 && li + 1 < segs.length) {
      final n = int.tryParse(segs[li + 1]);
      if (n != null) return FastApiPurchaseScrollHint.line(n);
    }
  }
  return null;
}
