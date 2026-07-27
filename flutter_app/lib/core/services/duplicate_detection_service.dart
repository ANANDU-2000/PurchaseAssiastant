import 'dart:async';

import '../api/hexa_api.dart';

/// Debounced server fuzzy check for catalog item names (see GET …/catalog/fuzzy-check).
final class CatalogDuplicateDebouncer {
  CatalogDuplicateDebouncer(this._api);

  final HexaApi _api;
  Timer? _timer;

  /// [onResult] runs on the same isolate after the debounce window.
  void schedule({
    required String businessId,
    required String name,
    String? supplierId,
    String? categoryId,
    String? typeId,
    required void Function(List<Map<String, dynamic>> hits) onResult,
    Duration debounce = const Duration(milliseconds: 300),
  }) {
    _timer?.cancel();
    final q = name.trim();
    if (q.length < 2) {
      onResult(const []);
      return;
    }
    _timer = Timer(debounce, () async {
      try {
        final hits = await _api.catalogFuzzyCheck(
          businessId: businessId,
          name: q,
          supplierId: supplierId,
          categoryId: categoryId,
          typeId: typeId,
        );
        onResult(hits);
      } catch (_) {
        onResult(const []);
      }
    });
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}

double fuzzyHitScore(Map<String, dynamic> hit) {
  final s = hit['score'];
  if (s is num) return s.toDouble();
  return double.tryParse(s?.toString() ?? '') ?? 0;
}
