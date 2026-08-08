import 'package:flutter/foundation.dart';

/// Debug-only counters for Stock tab API storms (list / shell-bundle / audit / alerts).
///
/// Call [noteStockGet] from Dio for matching GET paths. Logs a summary every
/// [window] when any counted request completes.
class StockApiStormMonitor {
  StockApiStormMonitor._();

  static const Duration window = Duration(seconds: 10);

  static DateTime? _windowStart;
  static final Map<String, int> _counts = {};
  static final Map<String, int> _msSum = {};
  static final Map<String, int> _msMax = {};

  static String? classifyStockGetPath(String path) {
    final p = path.toLowerCase();
    if (p.contains('/stock/shell-bundle')) return 'shell-bundle';
    if (p.contains('/stock/audit/recent') || p.contains('/stock/audit/feed')) {
      return 'audit/recent';
    }
    if (p.contains('/stock/alerts/summary') ||
        p.contains('/stock/status-counts')) {
      return 'alerts/summary';
    }
    if (p.contains('/stock/delivery-indicator-counts')) {
      return 'delivery-counts';
    }
    if (p.contains('/stock/list') || RegExp(r'/stock/?$').hasMatch(p)) {
      return 'stock/list';
    }
    return null;
  }

  static void noteStockGet({
    required String path,
    required int elapsedMs,
    String? requestId,
  }) {
    if (!kDebugMode) return;
    final key = classifyStockGetPath(path);
    if (key == null) return;

    final now = DateTime.now();
    _windowStart ??= now;
    if (now.difference(_windowStart!) > window) {
      _flush(reason: 'window_elapsed');
      _windowStart = now;
    }

    _counts[key] = (_counts[key] ?? 0) + 1;
    _msSum[key] = (_msSum[key] ?? 0) + elapsedMs;
    final prevMax = _msMax[key] ?? 0;
    if (elapsedMs > prevMax) _msMax[key] = elapsedMs;

    if (requestId != null && requestId.isNotEmpty) {
      debugPrint(
        '[STOCK_STORM] $key ${elapsedMs}ms x-request-id=$requestId path=$path',
      );
    }
  }

  static void _flush({required String reason}) {
    if (_counts.isEmpty) return;
    final parts = _counts.keys.map((k) {
      final n = _counts[k] ?? 0;
      final sum = _msSum[k] ?? 0;
      final max = _msMax[k] ?? 0;
      final avg = n == 0 ? 0 : (sum / n).round();
      return '$k×$n(avg=${avg}ms,max=${max}ms)';
    }).join(' ');
    debugPrint('[STOCK_STORM_SUMMARY] $reason $parts');
    _counts.clear();
    _msSum.clear();
    _msMax.clear();
  }

  /// Force a summary (e.g. after Activity tab open or physical save).
  static void flushNow({String reason = 'manual'}) {
    if (!kDebugMode) return;
    _flush(reason: reason);
    _windowStart = DateTime.now();
  }
}
