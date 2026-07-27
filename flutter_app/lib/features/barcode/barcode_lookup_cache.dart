/// In-memory barcode → stock row cache (fast re-scans; server also caches).
class BarcodeLookupCache {
  BarcodeLookupCache._();

  static const _ttl = Duration(minutes: 10);
  static const _maxEntries = 64;

  static final _entries = <String, _CacheEntry>{};

  static String _key(String businessId, String code) =>
      '$businessId::${code.trim().toLowerCase()}';

  static Map<String, dynamic>? get(String businessId, String code) {
    final k = _key(businessId, code);
    final e = _entries[k];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > _ttl) {
      _entries.remove(k);
      return null;
    }
    return Map<String, dynamic>.from(e.row);
  }

  static void put(String businessId, String code, Map<String, dynamic> row) {
    if (_entries.length >= _maxEntries) {
      final oldest = _entries.entries.reduce(
        (a, b) => a.value.at.isBefore(b.value.at) ? a : b,
      );
      _entries.remove(oldest.key);
    }
    _entries[_key(businessId, code)] = _CacheEntry(
      row: Map<String, dynamic>.from(row),
      at: DateTime.now(),
    );
  }

  static void clear() => _entries.clear();
}

class _CacheEntry {
  _CacheEntry({required this.row, required this.at});

  final Map<String, dynamic> row;
  final DateTime at;
}
