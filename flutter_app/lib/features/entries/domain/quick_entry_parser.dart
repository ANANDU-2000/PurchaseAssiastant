/// Parses natural-language quick lines for purchase entry.
///
/// Supported shapes (right → left):
/// - `… item 43` → landing only
/// - `… item 43 aju` → landing + supplier word after price
/// - `… item 43 aju 46` → landing + supplier + selling (two trailing numbers)
/// - `… Basmati 50kg 1200` → composite qty+unit token
class QuickParseResult {
  const QuickParseResult({
    required this.itemName,
    required this.qty,
    required this.unit,
    required this.landing,
    this.selling,
    this.supplierHint,
  });

  final String itemName;
  final double qty;
  final String unit;
  final double landing;
  final double? selling;
  final String? supplierHint;
}

bool _isNum(String s) => double.tryParse(s) != null;

/// [supplierNamesLower] — optional supplier names (lowercase) to peel the last word
/// after prices (e.g. `aju` matching catalog supplier "Aju Traders").
QuickParseResult? parseQuickLine(String raw,
    {Iterable<String> supplierNamesLower = const []}) {
  var t = raw.trim().split(RegExp(r'\s+'));
  if (t.length < 2) return null;

  final supplierSet = supplierNamesLower
      .map((s) => s.trim().toLowerCase())
      .where((s) => s.isNotEmpty)
      .toSet();

  /// `… 43 aju` → peel `aju` before reading numbers
  String? peeledSupplier;
  if (t.length >= 2 && !_isNum(t.last) && _isNum(t[t.length - 2])) {
    peeledSupplier = t.removeLast();
  }

  final nums = <double>[];
  while (t.isNotEmpty && _isNum(t.last) && nums.length < 2) {
    nums.add(double.parse(t.removeLast()));
  }
  if (nums.isEmpty) return null;

  double landing;
  double? selling;
  if (nums.length == 1) {
    landing = nums.first;
  } else {
    selling = nums.first;
    landing = nums.last;
  }

  /// After prices, optional supplier word (e.g. `rice vaani aju` left)
  String? supplierHint = peeledSupplier;
  if (supplierHint == null && t.isNotEmpty) {
    final cand = t.last.toLowerCase();
    final match = supplierSet.contains(cand) ||
        supplierSet.any((s) =>
            s.contains(cand) ||
            cand.contains(s) ||
            s.startsWith(cand) ||
            cand.startsWith(s));
    if (match && t.length >= 2) {
      supplierHint = t.removeLast();
    }
  }

  if (t.isEmpty) {
    if (supplierHint == null) return null;
    return QuickParseResult(
      itemName: supplierHint,
      qty: 1,
      unit: 'kg',
      landing: landing,
      selling: selling,
      supplierHint: null,
    );
  }

  double qty = 1;
  String unit = 'kg';
  late String itemName;
  final maybeQtyUnit = t.last;
  final um =
      RegExp(r'^(\d+(?:\.\d+)?)(kg|box|pcs?|piece)$', caseSensitive: false)
          .firstMatch(maybeQtyUnit);
  if (um != null) {
    qty = double.tryParse(um.group(1)!) ?? 1;
    final u = um.group(2)!.toLowerCase();
    unit = u == 'box'
        ? 'box'
        : (u == 'pc' || u == 'pcs' || u == 'piece')
            ? 'piece'
            : 'kg';
    t.removeLast();
    itemName = t.join(' ');
  } else {
    final q = double.tryParse(maybeQtyUnit);
    if (q != null && t.length > 1) {
      qty = q;
      t.removeLast();
      itemName = t.join(' ');
    } else if (t.length == 1) {
      itemName = t.first;
      qty = 1;
    } else {
      final q2 = double.tryParse(t.last);
      if (q2 != null && t.length >= 2) {
        qty = q2;
        t.removeLast();
        itemName = t.join(' ');
      } else {
        itemName = t.join(' ');
      }
    }
  }

  final name = itemName.trim();
  if (name.isEmpty) return null;

  return QuickParseResult(
    itemName: name,
    qty: qty,
    unit: unit,
    landing: landing,
    selling: selling,
    supplierHint:
        supplierHint?.trim().isEmpty ?? true ? null : supplierHint!.trim(),
  );
}
