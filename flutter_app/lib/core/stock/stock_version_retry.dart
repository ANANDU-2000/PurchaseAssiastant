import 'package:dio/dio.dart';

/// Thrown after a second 409 [STALE_STOCK_VERSION] on stock save.
class StaleStockConflict implements Exception {
  StaleStockConflict({
    required this.currentVersion,
    this.currentStock,
  });

  final int currentVersion;
  final String? currentStock;

  static const userMessage =
      'Stock was updated by another user. Please review and try again.';

  @override
  String toString() => userMessage;
}

/// Reads optimistic-lock version from a stock/catalog row map.
int? stockVersionFromItem(Map<String, dynamic> item) {
  final v = item['stock_version'];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '');
}

/// Parses 409 `STALE_STOCK_VERSION` from API error body.
StaleStockConflict? parseStaleStockConflict(Object error) {
  if (error is StaleStockConflict) return error;
  if (error is! DioException || error.response?.statusCode != 409) {
    return null;
  }
  final data = error.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! Map) return null;
  if (detail['code']?.toString() != 'STALE_STOCK_VERSION') return null;
  final ver = detail['stock_version'];
  final version = ver is int
      ? ver
      : ver is num
          ? ver.toInt()
          : int.tryParse(ver?.toString() ?? '');
  if (version == null) return null;
  return StaleStockConflict(
    currentVersion: version,
    currentStock: detail['current_stock']?.toString(),
  );
}

/// Runs [operation] with optimistic version; on first stale 409 retries once silently.
Future<T> runWithStockVersionRetry<T>({
  required Future<T> Function(int? lastSeenVersion) operation,
  int? initialVersion,
  int maxAttempts = 2,
}) async {
  var version = initialVersion;
  Object? lastError;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await operation(version);
    } catch (e) {
      lastError = e;
      final stale = parseStaleStockConflict(e);
      if (stale == null || attempt >= maxAttempts - 1) {
        if (stale != null) throw stale;
        rethrow;
      }
      version = stale.currentVersion;
    }
  }
  if (lastError != null) {
    Error.throwWithStackTrace(lastError, StackTrace.current);
  }
  throw StateError('runWithStockVersionRetry: no attempts');
}
