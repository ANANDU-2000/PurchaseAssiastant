/// Safe coercion for JSON / API map values that may be [num], [String], or null.
/// Prevents `type 'String' is not a subtype of type 'num?'` when backends emit decimals as strings.
library;

double coerceToDouble(Object? v) {
  final n = coerceToDoubleNullable(v);
  return n ?? 0;
}

double? coerceToDoubleNullable(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) {
    final s = v.trim().replaceAll(',', '');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }
  return double.tryParse(v.toString().trim().replaceAll(',', ''));
}

int coerceToInt(Object? v, {int fallback = 0}) {
  final d = coerceToDoubleNullable(v);
  if (d == null) return fallback;
  return d.round();
}

int? coerceToIntNullable(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final d = coerceToDoubleNullable(v);
  if (d == null) return null;
  return d.round();
}
