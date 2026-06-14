import '../auth/provider_api_guard.dart';

/// Thrown when stock list must not return an empty success payload (auth gate / no session).
class StockListFetchBlockedException implements Exception {
  const StockListFetchBlockedException([this.reason]);

  final String? reason;

  @override
  String toString() => 'StockListFetchBlockedException(${reason ?? 'blocked'})';
}

bool isStockListAuthFailure(Object? error) {
  if (error is! StockListFetchBlockedException) return false;
  switch (error.reason) {
    case 'no_session':
    case 'business_mismatch':
      return true;
    case 'api_gate':
    case 'tab_not_visible':
      return false;
    default:
      return false;
  }
}

/// Transient pause (auth refresh, tab hidden) — not a sign-in failure.
bool isStockListTransientBlock(Object? error) {
  if (error is! StockListFetchBlockedException) return false;
  return error.reason == 'api_gate' ||
      error.reason == 'tab_not_visible' ||
      error.reason == 'etag_stale';
}

/// Item detail / stock row fetches — loading skeleton, not hard error.
bool isTransientStockFetchError(Object? error) {
  if (error is ProviderFetchAborted) return true;
  return isStockListTransientBlock(error);
}
