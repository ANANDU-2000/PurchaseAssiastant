import 'package:dio/dio.dart';

/// One retry after [delay] on [DioExceptionType.connectionTimeout] (cold PaaS wake).
class HexaConnectionTimeoutRetryInterceptor extends Interceptor {
  HexaConnectionTimeoutRetryInterceptor(
    this._dio, {
    this.delay = const Duration(seconds: 3),
  });

  final Dio _dio;
  final Duration delay;

  static const _retriedKey = 'conn_timeout_retried';

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.type != DioExceptionType.connectionTimeout ||
        err.requestOptions.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    err.requestOptions.extra[_retriedKey] = true;
    await Future<void>.delayed(delay);
    try {
      final res = await _dio.fetch(err.requestOptions);
      return handler.resolve(res);
    } on DioException catch (e) {
      return handler.next(e);
    }
  }
}
