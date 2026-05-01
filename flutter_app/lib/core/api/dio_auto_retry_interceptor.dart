import 'package:dio/dio.dart';

/// Retries safe, idempotent requests up to [maxAttempts] on transient failures.
/// Register on the main [Dio] after other interceptors; [onError] order is last-registered first.
class DioAutoRetryInterceptor extends Interceptor {
  DioAutoRetryInterceptor(this._dio, {this.maxAttempts = 3});

  final Dio _dio;
  /// Retry rounds after the first failure (each round: 1s, 2s, 4s delay).
  final int maxAttempts;

  bool _retryable(DioException err) {
    if (err.requestOptions.extra['skipAutoRetry'] == true) return false;
    final m = err.requestOptions.method.toUpperCase();
    if (m != 'GET' && m != 'HEAD') return false;
    final t = err.type;
    if (t == DioExceptionType.connectionError ||
        t == DioExceptionType.connectionTimeout ||
        t == DioExceptionType.sendTimeout ||
        t == DioExceptionType.receiveTimeout) {
      return true;
    }
    final sc = err.response?.statusCode;
    return sc == 502 || sc == 503 || sc == 504 || sc == 500;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (!_retryable(err)) {
      return handler.next(err);
    }
    var current = err;
    var n = (current.requestOptions.extra['dio_auto_retry'] as int?) ?? 0;
    while (n < maxAttempts) {
      n += 1;
      current.requestOptions.extra['dio_auto_retry'] = n;
      await Future<void>.delayed(Duration(milliseconds: 1000 * (1 << (n - 1))));
      try {
        final res = await _dio.fetch(current.requestOptions);
        return handler.resolve(res);
      } on DioException catch (e) {
        if (!_retryable(e)) {
          return handler.next(e);
        }
        current = e;
        if (n >= maxAttempts) {
          return handler.next(e);
        }
      }
    }
    return handler.next(current);
  }
}
