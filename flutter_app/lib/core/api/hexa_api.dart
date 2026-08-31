import 'dart:convert' show jsonEncode;
import 'dart:math' show Random, min;
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:http_parser/http_parser.dart';

import 'dio_auto_retry_interceptor.dart';
import '../auth/auth_error_messages.dart' show dioIsAutoRetryableTransport;
import '../config/app_config.dart';
import '../debug/agent_debug_log.dart';
import '../debug/stock_api_storm_monitor.dart';
import '../json_coerce.dart';
import '../models/session.dart';
import '../stock/stock_version_retry.dart';
import '../strict_decimal.dart';

part 'hexa_api_auth.dart';
part 'hexa_api_notifications.dart';
part 'hexa_api_users.dart';
part 'hexa_api_purchase.dart';
part 'hexa_api_reports.dart';
part 'hexa_api_contacts.dart';
part 'hexa_api_catalog.dart';
part 'hexa_api_stock.dart';
part 'hexa_api_settings.dart';

bool _reports404HintLogged = false;

void _noteStockStormTiming(RequestOptions options, {required bool ok}) {
  if (!kDebugMode) return;
  if (options.method.toUpperCase() != 'GET') return;
  final started = options.extra['_stock_storm_sw'];
  final ms = started is int
      ? DateTime.now().millisecondsSinceEpoch - started
      : 0;
  final rid = options.headers['x-request-id']?.toString() ??
      options.headers['X-Request-Id']?.toString();
  StockApiStormMonitor.noteStockGet(
    path: options.uri.path,
    elapsedMs: ms < 0 ? 0 : ms,
    requestId: rid,
  );
  if (kDebugMode && StockApiStormMonitor.classifyStockGetPath(options.uri.path) != null) {
    debugPrint(
      '[STOCK_TIMING] ${ok ? 'ok' : 'err'} ${options.uri.path} ${ms}ms '
      'x-request-id=${rid ?? '-'}',
    );
  }
}

/// Correlates app failures with Render/API logs (echoed as `X-Request-Id`).
String _newRequestCorrelationId() {
  const hex = '0123456789abcdef';
  final r = Random();
  String seg(int n) => List.generate(n, (_) => hex[r.nextInt(16)]).join();
  return '${seg(8)}-${seg(4)}-${seg(4)}-${seg(4)}-${seg(12)}';
}

/// Trade report endpoints normally return a JSON array; tolerate wrapped maps.
List<Map<String, dynamic>> _parseJsonMapList(dynamic data) {
  if (data is List) {
    return data
        .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
        .whereType<Map<String, dynamic>>()
        .toList();
  }
  if (data is Map) {
    for (final key in const ['items', 'data', 'rows', 'results']) {
      final inner = data[key];
      final out = _parseJsonMapList(inner);
      if (out.isNotEmpty) return out;
    }
  }
  return [];
}

/// Bill scans removed — keep stock write timeouts only.
Options get _stockWriteOptions => Options(
      sendTimeout: const Duration(seconds: 45),
      receiveTimeout: const Duration(seconds: 90),
      connectTimeout: const Duration(seconds: 60),
    );

/// Deterministic idempotency key: hash of the request body with a random
/// fallback — mirrors `OfflineSyncService.fingerprintForTradePurchaseCreate`.
String _idempotencyKeyFor(Map<String, dynamic> body) {
  try {
    final canonical = jsonEncode(body);
    final h = canonical.hashCode;
    final r = Random();
    String seg(int n) =>
        List.generate(n, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
    final uuid = '${seg(8)}-${seg(4)}-4${seg(3)}-${seg(4)}-${seg(12)}';
    return '$h:$uuid';
  } catch (_) {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

bool _isAuthEndpoint(String path) {
  return path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/google') ||
      path.contains('/auth/refresh') ||
      path.contains('/auth/forgot-password') ||
      path.contains('/auth/reset-password');
}

class _BusinessConnectivityBannerInterceptor extends Interceptor {
  _BusinessConnectivityBannerInterceptor(this._fn);

  final void Function(bool degraded, String? hint)? _fn;

  static bool _biz(String p) => p.startsWith('/v1/') && !_isAuthEndpoint(p);

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final fn = _fn;
    final path = response.requestOptions.uri.path;
    if (fn != null &&
        _biz(path) &&
        response.statusCode != null &&
        response.statusCode! >= 200 &&
        response.statusCode! < 300) {
      final dbDown = response.headers.value('x-database-unavailable') == '1';
      if (dbDown) {
        fn(true, 'Database temporarily unavailable');
      } else {
        fn(false, null);
      }
    }
    return handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final fn = _fn;
    final path = err.requestOptions.uri.path;
    if (fn != null && _biz(path) && !_isAuthEndpoint(path)) {
      final sc = err.response?.statusCode;
      if (sc == 503) {
        final h = err.response?.headers.value('x-database-unavailable');
        fn(
          true,
          h == '1'
              ? 'Database temporarily unavailable'
              : 'Waking server (~30s) — retrying automatically',
        );
      } else if (dioIsAutoRetryableTransport(err) ||
          (sc != null && sc >= 502 && sc <= 504)) {
        fn(true, null);
      }
    }
    return handler.next(err);
  }
}

class HexaApiBase {
  HexaApiBase({
    String? baseUrl,
    Future<bool> Function()? onUnauthorizedRefresh,
    Future<void> Function(String reason)? onTerminalAuthFailure,
    Future<String?> Function()? resolveAccessToken,
    void Function(bool degraded, String? hint)? onConnectivityBanner,
    bool Function()? authSessionExpired,
    bool Function()? onBusiness401,
    void Function()? onSuspendForAuthFailure,
    bool Function()? blockBusinessApi,
  })  : _onUnauthorizedRefresh = onUnauthorizedRefresh,
        _onTerminalAuthFailure = onTerminalAuthFailure,
        _resolveAccessToken = resolveAccessToken,
        _onConnectivityBanner = onConnectivityBanner,
        _authSessionExpired = authSessionExpired,
        _onBusiness401 = onBusiness401,
        _onSuspendForAuthFailure = onSuspendForAuthFailure,
        _blockBusinessApi = blockBusinessApi,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.resolvedApiBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
            headers: const {
              'X-Requested-With': 'harisree-app',
            },
          ),
        ),
        _plain = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.resolvedApiBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
            headers: const {
              'X-Requested-With': 'harisree-app',
            },
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final h = options.headers;
          final raw = h['x-request-id'] ?? h['X-Request-Id'];
          final s = raw?.toString().trim() ?? '';
          if (s.isEmpty) {
            h['x-request-id'] = _newRequestCorrelationId();
          }
          options.extra['_stock_storm_sw'] = DateTime.now().millisecondsSinceEpoch;
          return handler.next(options);
        },
        onResponse: (response, handler) {
          _noteStockStormTiming(response.requestOptions, ok: true);
          // #region agent log
          final started = response.requestOptions.extra['_stock_storm_sw'];
          if (started is int) {
            final ms = DateTime.now().millisecondsSinceEpoch - started;
            if (ms >= 400) {
              agentDebugLog(
                hypothesisId: 'H3',
                location: 'hexa_api.dart:onResponse',
                message: 'slow_api',
                data: {
                  'path': response.requestOptions.uri.path,
                  'method': response.requestOptions.method,
                  'ms': ms,
                  'status': response.statusCode,
                },
              );
            }
          }
          // #endregion
          return handler.next(response);
        },
        onError: (DioException err, ErrorInterceptorHandler handler) {
          _noteStockStormTiming(err.requestOptions, ok: false);
          return handler.next(err);
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        // Belt-and-suspenders: if a request goes out without an Authorization
        // header (e.g. cold start fires before SessionNotifier.restore has
        // called setAuthToken), resolve the token from the secure store and
        // attach it. Skips auth endpoints. Prevents the "empty dashboard,
        // random 401s on first paint" class of bugs.
        onRequest: (options, handler) async {
          final path = options.uri.path;
          if (_isAuthEndpoint(path)) {
            return handler.next(options);
          }
          if (_blockBusinessApi?.call() == true) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                message: 'auth_blocked',
              ),
            );
          }
          final existing = options.headers['Authorization']?.toString() ??
              _dio.options.headers['Authorization']?.toString();
          if (existing == null || existing.isEmpty) {
            final resolver = _resolveAccessToken;
            if (resolver != null) {
              final tokenSw = Stopwatch()..start();
              try {
                final token = await resolver();
                // #region agent log
                if (tokenSw.elapsedMilliseconds >= 80) {
                  agentDebugLog(
                    hypothesisId: 'H4',
                    location: 'hexa_api.dart:onRequest',
                    message: 'slow_token_resolve',
                    data: {
                      'path': path,
                      'ms': tokenSw.elapsedMilliseconds,
                      'hadToken': token != null && token.isNotEmpty,
                    },
                  );
                }
                // #endregion
                if (token != null && token.isNotEmpty) {
                  final h = 'Bearer $token';
                  _dio.options.headers['Authorization'] = h;
                  options.headers['Authorization'] = h;
                }
              } catch (_) {
                // Resolver failed; let the request go and 401 interceptor handle it.
              }
            }
          }
          return handler.next(options);
        },
        onError: (DioException err, ErrorInterceptorHandler handler) async {
          final sc = err.response?.statusCode;
          final path = err.requestOptions.uri.path;
          final isAuthFailure =
              sc == 401 || (sc == 403 && path.startsWith('/v1/businesses/'));
          if (!isAuthFailure) {
            return handler.next(err);
          }
          final req = err.requestOptions;
          if (_isAuthEndpoint(path)) {
            return handler.next(err);
          }
          if (_authSessionExpired?.call() == true) {
            return handler.next(err);
          }
          if (_onBusiness401?.call() == true) {
            await _onTerminalAuthFailure?.call('auth_circuit_open');
            return handler.next(err);
          }
          _onSuspendForAuthFailure?.call();
          if (req.extra['authRetried'] == true) {
            await _onTerminalAuthFailure?.call('auth_retry_failed');
            return handler.next(err);
          }
          // Refresh first — expired access tokens are normal after redeploy;
          // do not suspend the API until refresh actually fails.
          final ok = await _onUnauthorizedRefresh?.call() ?? false;
          if (!ok) {
            await _onTerminalAuthFailure?.call('refresh_failed');
            return handler.next(err);
          }
          final auth = _dio.options.headers['Authorization'];
          if (auth != null) {
            req.headers['Authorization'] = auth;
          }
          req.extra['authRetried'] = true;
          try {
            final res = await _dio.fetch(req);
            return handler.resolve(res);
          } on DioException catch (e) {
            if (e.response?.statusCode == 401 ||
                e.response?.statusCode == 403) {
              await _onTerminalAuthFailure?.call('auth_retry_failed');
            }
            return handler.next(e);
          }
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException err, ErrorInterceptorHandler handler) {
          if (kDebugMode) {
            final req = err.requestOptions;
            final sent = req.headers['x-request-id']?.toString();
            final echoed = err.response?.headers.value('x-request-id') ??
                err.response?.headers.value('X-Request-Id');
            if ((sent != null && sent.isNotEmpty) ||
                (echoed != null && echoed.isNotEmpty)) {
              debugPrint(
                'HexaApi: ${req.uri.path} x-request-id=${echoed ?? sent} '
                '(search this id in API / Render logs)',
              );
            }
          }
          if (err.response?.statusCode == 404) {
            final p = err.requestOptions.uri.path;
            if (p.contains('/reports/') && !_reports404HintLogged) {
              _reports404HintLogged = true;
              debugPrint(
                'HexaApi: 404 on a reports request ($p). If your backend includes '
                'the reports routes (e.g. reports/trade-suppliers), restart the API from '
                'the current `main` and point the app at the same base URL and port as '
                'the running server.',
              );
            }
          }
          return handler.next(err);
        },
      ),
    );
    _dio.interceptors.add(DioAutoRetryInterceptor(_dio, maxAttempts: 2));
    final banner = _onConnectivityBanner;
    if (banner != null) {
      _dio.interceptors.add(_BusinessConnectivityBannerInterceptor(banner));
    }
  }

  final Dio _dio;
  final Dio _plain;
  final Future<bool> Function()? _onUnauthorizedRefresh;
  final Future<void> Function(String reason)? _onTerminalAuthFailure;
  final Future<String?> Function()? _resolveAccessToken;
  final void Function(bool degraded, String? hint)? _onConnectivityBanner;
  final bool Function()? _authSessionExpired;
  final bool Function()? _onBusiness401;
  final void Function()? _onSuspendForAuthFailure;
  final bool Function()? _blockBusinessApi;

  Dio get raw => _dio;

  /// Public health check (no auth). Used for AI status indicator.

  /// Public health check (no auth). Used for AI status indicator.
  Future<Map<String, dynamic>> health() async {
    final res = await _plain.get<Map<String, dynamic>>('/health');
    return res.data ?? <String, dynamic>{};
  }

  /// Instant liveness (no DB) — warmup and Render wake.

  /// Instant liveness (no DB) — warmup and Render wake.
  Future<Map<String, dynamic>> healthLive() async {
    final res = await _plain.get<Map<String, dynamic>>('/health/live');
    return res.data ?? <String, dynamic>{};
  }

  /// DB readiness probe (503 when DB unreachable).

  /// DB readiness probe (503 when DB unreachable).
  Future<Map<String, dynamic>> healthReady() async {
    final res = await _plain.get<Map<String, dynamic>>('/health/ready');
    return res.data ?? <String, dynamic>{};
  }


  Future<List<Map<String, dynamic>>> listRealtimeEvents({
    required String businessId,
    int limit = 50,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/realtime/recent',
      queryParameters: {'limit': limit},
      options: Options(extra: const {'skipAutoRetry': true}),
    );
    return _parseJsonMapList(res.data);
  }


  void setAuthToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }


  ({String access, String refresh}) _tokenPairFromResponse(
      Response<Map<String, dynamic>> res) {
    final d = res.data!;
    return (
      access: (d['access_token'] as String?) ?? '',
      refresh: (d['refresh_token'] as String?) ?? '',
    );
  }

}

class HexaApi extends HexaApiBase with HexaApiAuthMethods, HexaApiNotificationsMethods, HexaApiUsersMethods, HexaApiPurchaseMethods, HexaApiReportsMethods, HexaApiContactsMethods, HexaApiCatalogMethods, HexaApiStockMethods, HexaApiSettingsMethods {
  /// Max rows for [listStockAuditRecent] (must match backend `le` on `/audit/recent`).
  static const int stockAuditRecentMaxLimit = 250;

  /// Max page size for [listLowStockOperations] (must match backend `le=200`).
  static const int lowStockOperationsMaxPerPage = 200;

  HexaApi({
    String? baseUrl,
    Future<bool> Function()? onUnauthorizedRefresh,
    Future<void> Function(String reason)? onTerminalAuthFailure,
    Future<String?> Function()? resolveAccessToken,
    void Function(bool degraded, String? hint)? onConnectivityBanner,
    bool Function()? authSessionExpired,
    bool Function()? onBusiness401,
    void Function()? onSuspendForAuthFailure,
    bool Function()? blockBusinessApi,
  }) : super(
          baseUrl: baseUrl,
          onUnauthorizedRefresh: onUnauthorizedRefresh,
          onTerminalAuthFailure: onTerminalAuthFailure,
          resolveAccessToken: resolveAccessToken,
          onConnectivityBanner: onConnectivityBanner,
          authSessionExpired: authSessionExpired,
          onBusiness401: onBusiness401,
          onSuspendForAuthFailure: onSuspendForAuthFailure,
          blockBusinessApi: blockBusinessApi,
        );
}

