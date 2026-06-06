import 'package:dio/dio.dart';

/// Thrown when a stock write hits a DB constraint (409 integrity_error) — not a version conflict.
class StockIntegrityError implements Exception {
  StockIntegrityError();

  static const userMessage =
      'Database schema not up to date. Ask owner to update the server.';

  @override
  String toString() => userMessage;
}

/// Thrown after stock save retries are exhausted (409 [STALE_STOCK_VERSION]).
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

/// Parses 409 integrity_error (missing migration / CHECK constraint) — do not retry.
StockIntegrityError? parseStockIntegrityError(Object error) {
  if (error is StockIntegrityError) return error;
  if (error is! DioException || error.response?.statusCode != 409) {
    return null;
  }
  final data = error.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is String && detail.trim() == 'integrity_error') {
    return StockIntegrityError();
  }
  if (detail is Map) {
    final code = detail['code']?.toString() ?? '';
    if (code == 'integrity_error') {
      return StockIntegrityError();
    }
  }
  return null;
}

/// Parses 409 stock-version conflicts from API error body.
StaleStockConflict? parseStaleStockConflict(Object error) {
  if (error is StaleStockConflict) return error;
  if (error is! DioException || error.response?.statusCode != 409) {
    return null;
  }
  final data = error.response?.data;
  if (data is! Map) return null;
  final detail = data['detail'];
  if (detail is! Map) return null;
  final code = detail['code']?.toString();
  if (code != 'STALE_STOCK_VERSION' && code != 'STOCK_VERSION_CONFLICT') {
    return null;
  }
  final ver = detail['stock_version'] ?? detail['current_version'];
  final version = ver is int
      ? ver
      : ver is num
          ? ver.toInt()
          : int.tryParse(ver?.toString() ?? '');
  if (version == null) return null;
  return StaleStockConflict(
    currentVersion: version,
    currentStock:
        (detail['current_stock'] ?? detail['current_qty'])?.toString(),
  );
}

/// Stock write with optimistic [stock_version].
///
/// Retries with server version from 409, then on the last attempt may pass
/// [force] so the API can apply the edit after explicit conflict handling.
typedef StockVersionOperation<T> = Future<T> Function(
  int? lastSeenVersion, {
  bool force,
});

/// Runs [operation] with optimistic version.
Future<T> runWithStockVersionRetry<T>({
  required StockVersionOperation<T> operation,
  Future<int?> Function()? refreshVersion,
  int? initialVersion,
  int maxAttempts = 3,
}) async {
  var version = initialVersion;
  Object? lastError;
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final isLast = attempt >= maxAttempts - 1;
    try {
      return await operation(version, force: false);
    } catch (e) {
      lastError = e;
      final integrity = parseStockIntegrityError(e);
      if (integrity != null) {
        throw integrity;
      }
      if (e is DioException && e.response?.statusCode == 409) {
        final data = e.response?.data;
        if (data is Map) {
          final detail = data['detail'];
          if (detail is Map) {
            final code = detail['code']?.toString() ?? '';
            if (code != 'STALE_STOCK_VERSION' &&
                code != 'STOCK_VERSION_CONFLICT') {
              rethrow;
            }
          } else if (detail is! String || detail.trim() != 'integrity_error') {
            rethrow;
          }
        }
      }
      final stale = parseStaleStockConflict(e);
      if (stale == null) {
        rethrow;
      }
      if (isLast) {
        throw stale;
      }
      version = await refreshVersion?.call() ?? stale.currentVersion;
    }
  }
  if (lastError != null) {
    Error.throwWithStackTrace(lastError, StackTrace.current);
  }
  throw StateError('runWithStockVersionRetry: no attempts');
}
