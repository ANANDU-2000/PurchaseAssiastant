import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http_parser/http_parser.dart';

import 'dio_auto_retry_interceptor.dart';
import '../config/app_config.dart';
import '../models/session.dart';

/// Transient failures only — do not retry after a full response (avoids duplicate assistant turns).
bool _retryableAssistantRequest(DioException e) {
  final sc = e.response?.statusCode;
  if (sc != null && (sc == 502 || sc == 503 || sc == 504)) return true;
  final t = e.type;
  return t == DioExceptionType.connectionError ||
      t == DioExceptionType.connectionTimeout ||
      t == DioExceptionType.sendTimeout;
}

bool _reports404HintLogged = false;

bool _isAuthEndpoint(String path) {
  return path.contains('/auth/login') ||
      path.contains('/auth/register') ||
      path.contains('/auth/google') ||
      path.contains('/auth/refresh') ||
      path.contains('/auth/forgot-password') ||
      path.contains('/auth/reset-password');
}

class HexaApi {
  HexaApi({
    String? baseUrl,
    Future<bool> Function()? onUnauthorizedRefresh,
    Future<String?> Function()? resolveAccessToken,
  })  : _onUnauthorizedRefresh = onUnauthorizedRefresh,
        _resolveAccessToken = resolveAccessToken,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.resolvedApiBaseUrl,
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 15),
          ),
        ),
        _plain = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.resolvedApiBaseUrl,
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 15),
          ),
        ) {
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
          final existing = options.headers['Authorization']?.toString() ??
              _dio.options.headers['Authorization']?.toString();
          if (existing == null || existing.isEmpty) {
            final resolver = _resolveAccessToken;
            if (resolver != null) {
              try {
                final token = await resolver();
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
          if (err.response?.statusCode != 401) {
            return handler.next(err);
          }
          final req = err.requestOptions;
          if (req.extra['authRetried'] == true) {
            return handler.next(err);
          }
          if (_isAuthEndpoint(req.uri.path)) {
            return handler.next(err);
          }
          final ok = await _onUnauthorizedRefresh?.call() ?? false;
          if (!ok) {
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
            return handler.next(e);
          }
        },
      ),
    );
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException err, ErrorInterceptorHandler handler) {
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
    _dio.interceptors.add(DioAutoRetryInterceptor(_dio));
  }

  final Dio _dio;
  final Dio _plain;
  final Future<bool> Function()? _onUnauthorizedRefresh;
  final Future<String?> Function()? _resolveAccessToken;

  Dio get raw => _dio;

  /// Public health check (no auth). Used for AI status indicator.
  Future<Map<String, dynamic>> health() async {
    final res = await _plain.get<Map<String, dynamic>>('/health');
    return res.data ?? <String, dynamic>{};
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
      access: d['access_token'] as String,
      refresh: d['refresh_token'] as String
    );
  }

  Future<({String access, String refresh})> login(
      {required String email, required String password}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/login',
      data: {'email': email, 'password': password},
    );
    return _tokenPairFromResponse(res);
  }

  Future<({String access, String refresh})> register({
    required String username,
    required String email,
    required String password,
    String? name,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/register',
      data: {
        'username': username,
        'email': email,
        'password': password,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      },
    );
    return _tokenPairFromResponse(res);
  }

  Future<({String access, String refresh})> loginWithGoogle(
      {required String idToken}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/google',
      data: {'id_token': idToken},
    );
    return _tokenPairFromResponse(res);
  }

  /// Request a password reset (no auth). In development the response may include `dev_reset_token`.
  Future<Map<String, dynamic>> requestPasswordReset({required String email}) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/forgot-password',
      data: {'email': email.trim().toLowerCase()},
    );
    return res.data ?? <String, dynamic>{};
  }

  /// Apply new password using the token from the reset link (no auth).
  Future<Map<String, dynamic>> resetPasswordWithToken({
    required String token,
    required String newPassword,
  }) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/reset-password',
      data: {
        'token': token,
        'new_password': newPassword,
      },
    );
    return res.data ?? <String, dynamic>{};
  }

  /// No Bearer header — uses body only. Kept on [_plain] so it never inherits [setAuthToken].
  Future<({String access, String refresh})> refreshTokens(
      {required String refreshToken}) async {
    final res = await _plain.post<Map<String, dynamic>>(
      '/v1/auth/refresh',
      data: {'refresh_token': refreshToken},
    );
    return _tokenPairFromResponse(res);
  }

  Future<List<BusinessBrief>> meBusinesses() async {
    final res = await _dio.get<dynamic>('/v1/me/businesses');
    final data = res.data;
    if (data is! List) return [];
    return data
        .map((e) => BusinessBrief.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Idempotent: ensure default workspace + catalog/supplier seed (single-tenant).
  /// Returns body JSON: `business_id`, `created_business`, `seeded`, optional `seed_stats`.
  /// Returns null when the server has no route (older API: 404/501) so session boot can continue.
  Future<Map<String, dynamic>?> bootstrapWorkspace() async {
    try {
      final res = await _dio.post<Map<String, dynamic>>('/v1/me/bootstrap-workspace');
      final d = res.data;
      if (d is Map) return Map<String, dynamic>.from(d as Map);
      return null;
    } on DioException catch (e) {
      final sc = e.response?.statusCode;
      if (sc == 404 || sc == 501) {
        debugPrint(
            'hexa: bootstrap-workspace not available (HTTP $sc) — continuing without server seed');
        return null;
      }
      rethrow;
    }
  }

  /// Owner: optional in-app title + logo URL (HTTPS recommended).
  Future<Map<String, dynamic>> patchBusinessBranding({
    required String businessId,
    String? brandingTitle,
    String? brandingLogoUrl,
    String? gstNumber,
    String? address,
    String? phone,
    /// When true, always sends [contactEmail] (use empty string to clear).
    bool includeContactEmail = false,
    String? contactEmail,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/me/businesses/$businessId/branding',
      data: {
        if (brandingTitle != null) 'branding_title': brandingTitle,
        if (brandingLogoUrl != null) 'branding_logo_url': brandingLogoUrl,
        if (gstNumber != null) 'gst_number': gstNumber,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
        if (includeContactEmail) 'contact_email': (contactEmail ?? '').trim(),
      },
    );
    return res.data ?? {};
  }

  /// Owner: multipart logo upload (JPEG/PNG/WebP).
  Future<Map<String, dynamic>> uploadBusinessLogo({
    required String businessId,
    required String filePath,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/businesses/$businessId/branding/logo',
      data: formData,
    );
    return res.data ?? {};
  }

  /// Same as [uploadBusinessLogo] but from bytes (web-friendly).
  Future<Map<String, dynamic>> uploadBusinessLogoBytes({
    required String businessId,
    required List<int> bytes,
    String filename = 'logo.jpg',
  }) async {
    final lower = filename.toLowerCase();
    final MediaType ct;
    if (lower.endsWith('.png')) {
      ct = MediaType('image', 'png');
    } else if (lower.endsWith('.webp')) {
      ct = MediaType('image', 'webp');
    } else {
      ct = MediaType('image', 'jpeg');
    }
    final formData = FormData.fromMap({
      'file':
          MultipartFile.fromBytes(bytes, filename: filename, contentType: ct),
    });
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/me/businesses/$businessId/branding/logo',
      data: formData,
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> analyticsSummary(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/summary',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  /// Calendar-month composite dashboard (`month` = `YYYY-MM`). Full month window on server.
  Future<Map<String, dynamic>> getDashboard({
    required String businessId,
    required String month,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/dashboard',
      queryParameters: {'month': month},
    );
    return res.data ?? {};
  }

  /// Trade-purchase window insights (best/worst item by spend, supplier cost spread).
  Future<Map<String, dynamic>> analyticsInsights({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/insights/trade',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>?> getAnalyticsGoals({
    required String businessId,
    required String period,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/goals',
      queryParameters: {'period': period},
    );
    final d = res.data;
    if (d == null) return null;
    if (d is Map) return Map<String, dynamic>.from(d);
    return null;
  }

  Future<Map<String, dynamic>> putAnalyticsGoals({
    required String businessId,
    required String period,
    double? profitGoal,
    double? volumeGoal,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/goals',
      queryParameters: {'period': period},
      data: {
        if (profitGoal != null) 'profit_goal': profitGoal,
        if (volumeGoal != null) 'volume_goal': volumeGoal,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<List<dynamic>> listEntries({
    required String businessId,
    String? from,
    String? to,
    String? item,
    String? supplierId,
    String? brokerId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/entries',
      queryParameters: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (item != null && item.isNotEmpty) 'item': item,
        if (supplierId != null && supplierId.isNotEmpty)
          'supplier_id': supplierId,
        if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      },
    );
    final items = res.data?['items'];
    if (items is List) return items;
    return [];
  }

  /// Unified catalog items + suppliers + entries (server-side substring match).
  Future<Map<String, dynamic>> unifiedSearch({
    required String businessId,
    required String q,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/search',
      queryParameters: {'q': q},
    );
    return res.data ?? {};
  }

  /// Trade purchases (wholesale PUR-YYYY-XXXX flow).
  Future<List<Map<String, dynamic>>> listTradePurchases({
    required String businessId,
    int limit = 50,
    int offset = 0,
    String status = 'all',
    String? q,
    String? supplierId,
    String? brokerId,
    String? catalogItemId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/trade-purchases',
      queryParameters: {
        'limit': limit,
        'offset': offset,
        'status': status,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (supplierId != null && supplierId.trim().isNotEmpty)
          'supplier_id': supplierId.trim(),
        if (brokerId != null && brokerId.trim().isNotEmpty) 'broker_id': brokerId.trim(),
        if (catalogItemId != null && catalogItemId.trim().isNotEmpty)
          'catalog_item_id': catalogItemId.trim(),
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>?> getTradePurchaseDraft({
    required String businessId,
  }) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/v1/businesses/$businessId/trade-purchases/draft',
      );
      final d = res.data;
      if (d == null) return null;
      return Map<String, dynamic>.from(Map<Object?, Object?>.from(d));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      // Draft is optional UX convenience — avoid hard failures when API is
      // temporarily unreachable or slow.
      if (e.response == null) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> putTradePurchaseDraft({
    required String businessId,
    required int step,
    required Map<String, dynamic> payload,
  }) async {
    final res = await _dio.put<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/draft',
      data: {'step': step, 'payload': payload},
    );
    return res.data ?? {};
  }

  Future<void> deleteTradePurchaseDraft({required String businessId}) async {
    await _dio.delete<void>(
      '/v1/businesses/$businessId/trade-purchases/draft',
    );
  }

  Future<Map<String, dynamic>> checkTradePurchaseDuplicate({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/check-duplicate',
      data: body,
    );
    return res.data ?? {};
  }

  Future<String> nextTradePurchaseHumanId({
    required String businessId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/next-human-id',
    );
    final d = res.data ?? {};
    final id = d['human_id']?.toString();
    if (id == null || id.isEmpty) return '';
    return id;
  }

  Future<Map<String, dynamic>> createTradePurchase({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<dynamic>(
      '/v1/businesses/$businessId/trade-purchases',
      data: body,
    );
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> getTradePurchase({
    required String businessId,
    required String purchaseId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId',
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> updateTradePurchase({
    required String businessId,
    required String purchaseId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.put<dynamic>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId',
      data: body,
    );
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> patchPurchasePayment({
    required String businessId,
    required String purchaseId,
    required double paidAmount,
    String? paidAtIso,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/payment',
      data: {
        'paid_amount': paidAmount,
        if (paidAtIso != null && paidAtIso.isNotEmpty) 'paid_at': paidAtIso,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> markPurchasePaid({
    required String businessId,
    required String purchaseId,
    double? paidAmount,
    String? paidAtIso,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/mark-paid',
      data: {
        if (paidAmount != null) 'paid_amount': paidAmount,
        if (paidAtIso != null && paidAtIso.isNotEmpty) 'paid_at': paidAtIso,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<Map<String, dynamic>> cancelPurchase({
    required String businessId,
    required String purchaseId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/cancel',
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<void> deleteTradePurchase({
    required String businessId,
    required String purchaseId,
  }) async {
    await _dio.delete<void>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId',
    );
  }

  Future<Map<String, dynamic>> tradePurchaseSummary({
    required String businessId,
    String? from,
    String? to,
    String? supplierId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-summary',
      queryParameters: {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (supplierId != null && supplierId.isNotEmpty) 'supplier_id': supplierId,
      },
    );
    return res.data ?? {};
  }

  /// Trade purchase line aggregates (replaces legacy Entry-based `/analytics/items`).
  Future<List<Map<String, dynamic>>> tradeReportItems({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-items',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> tradeReportSuppliers({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-suppliers',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> tradeReportCategories({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-categories',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Subcategory (CategoryType) spend — matches catalog category → type → items.
  Future<List<Map<String, dynamic>>> tradeReportTypes({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-types',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Single call: same definitions as trade reports + nested category line items + mapping recs.
  Future<Map<String, dynamic>> tradeDashboardSnapshot({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-dashboard-snapshot',
      queryParameters: {'from': from, 'to': to},
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Per (item, supplier, broker) trade stats and best-supplier recommendations (deals≥2 vwap).
  Future<Map<String, dynamic>> tradeSupplierBrokerMap({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-supplier-broker-map',
      queryParameters: {'from': from, 'to': to},
    );
    return Map<String, dynamic>.from(res.data ?? {});
  }

  Future<List<Map<String, dynamic>>> listSuppliers(
      {required String businessId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/suppliers');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createSupplier({
    required String businessId,
    required String name,
    String? phone,
    String? whatsappNumber,
    String? location,
    String? brokerId,
    List<String>? brokerIds,
    String? gstNumber,
    String? address,
    String? notes,
    int? defaultPaymentDays,
    double? defaultDiscount,
    double? defaultDeliveredRate,
    double? defaultBilltyRate,
    String? freightType,
    bool aiMemoryEnabled = false,
    Map<String, dynamic>? preferences,
  }) async {
    final data = <String, dynamic>{
      'name': name,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      if (whatsappNumber != null && whatsappNumber.isNotEmpty)
        'whatsapp_number': whatsappNumber,
      if (location != null && location.isNotEmpty) 'location': location,
      if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      if (brokerIds != null && brokerIds.isNotEmpty) 'broker_ids': brokerIds,
      if (gstNumber != null && gstNumber.isNotEmpty) 'gst_number': gstNumber,
      if (address != null && address.isNotEmpty) 'address': address,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (defaultPaymentDays != null) 'default_payment_days': defaultPaymentDays,
      if (defaultDiscount != null) 'default_discount': defaultDiscount,
      if (defaultDeliveredRate != null)
        'default_delivered_rate': defaultDeliveredRate,
      if (defaultBilltyRate != null) 'default_billty_rate': defaultBilltyRate,
      if (freightType != null && freightType.isNotEmpty)
        'freight_type': freightType,
      'ai_memory_enabled': aiMemoryEnabled,
    };
    if (preferences != null) {
      final c = preferences['category_ids'];
      final t = preferences['type_ids'];
      final i = preferences['item_ids'];
      if ((c is List && c.isNotEmpty) ||
          (t is List && t.isNotEmpty) ||
          (i is List && i.isNotEmpty)) {
        data['preferences'] = preferences;
      }
    }
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers',
      data: data,
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> listBrokers(
      {required String businessId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/brokers');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getSupplier(
      {required String businessId, required String supplierId}) async {
    final res = await _dio
        .get<dynamic>('/v1/businesses/$businessId/suppliers/$supplierId');
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> getBroker(
      {required String businessId, required String brokerId}) async {
    final res =
        await _dio.get<dynamic>('/v1/businesses/$businessId/brokers/$brokerId');
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> createBroker({
    required String businessId,
    required String name,
    String? phone,
    String? whatsappNumber,
    String? location,
    String? notes,
    String commissionType = 'percent',
    double? commissionValue,
    List<String>? supplierIds,
    Map<String, dynamic>? preferences,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers',
      data: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (whatsappNumber != null && whatsappNumber.isNotEmpty)
          'whatsapp_number': whatsappNumber,
        if (location != null && location.isNotEmpty) 'location': location,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'commission_type': commissionType,
        if (commissionValue != null) 'commission_value': commissionValue,
        if (supplierIds != null) 'supplier_ids': supplierIds,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateSupplier({
    required String businessId,
    required String supplierId,
    String? name,
    String? phone,
    String? whatsappNumber,
    String? location,
    String? brokerId,
    List<String>? brokerIds,
    String? gstNumber,
    String? address,
    String? notes,
    int? defaultPaymentDays,
    double? defaultDiscount,
    double? defaultDeliveredRate,
    double? defaultBilltyRate,
    String? freightType,
    bool? aiMemoryEnabled,
    Map<String, dynamic>? preferences,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers/$supplierId',
      data: {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (whatsappNumber != null) 'whatsapp_number': whatsappNumber,
        if (location != null) 'location': location,
        if (brokerId != null) 'broker_id': brokerId,
        if (brokerIds != null) 'broker_ids': brokerIds,
        if (gstNumber != null) 'gst_number': gstNumber,
        if (address != null) 'address': address,
        if (notes != null) 'notes': notes,
        if (defaultPaymentDays != null)
          'default_payment_days': defaultPaymentDays,
        if (defaultDiscount != null) 'default_discount': defaultDiscount,
        if (defaultDeliveredRate != null)
          'default_delivered_rate': defaultDeliveredRate,
        if (defaultBilltyRate != null) 'default_billty_rate': defaultBilltyRate,
        if (freightType != null) 'freight_type': freightType,
        if (aiMemoryEnabled != null) 'ai_memory_enabled': aiMemoryEnabled,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return res.data ?? {};
  }

  Future<void> deleteSupplier(
      {required String businessId, required String supplierId}) async {
    await _dio.delete<void>('/v1/businesses/$businessId/suppliers/$supplierId');
  }

  Future<Map<String, dynamic>> updateBroker({
    required String businessId,
    required String brokerId,
    String? name,
    String? phone,
    String? whatsappNumber,
    String? location,
    String? notes,
    String? commissionType,
    double? commissionValue,
    List<String>? supplierIds,
    Map<String, dynamic>? preferences,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers/$brokerId',
      data: {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (whatsappNumber != null) 'whatsapp_number': whatsappNumber,
        if (location != null) 'location': location,
        if (notes != null) 'notes': notes,
        if (commissionType != null) 'commission_type': commissionType,
        if (commissionValue != null) 'commission_value': commissionValue,
        if (supplierIds != null) 'supplier_ids': supplierIds,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return res.data ?? {};
  }

  Future<void> deleteBroker(
      {required String businessId, required String brokerId}) async {
    await _dio.delete<void>('/v1/businesses/$businessId/brokers/$brokerId');
  }

  Future<List<Map<String, dynamic>>> listItemCategories(
      {required String businessId}) async {
    final res =
        await _dio.get<dynamic>('/v1/businesses/$businessId/item-categories');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createItemCategory(
      {required String businessId, required String name}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories',
      data: {'name': name},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateItemCategory({
    required String businessId,
    required String categoryId,
    required String name,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId',
      data: {'name': name},
    );
    return res.data ?? {};
  }

  Future<void> deleteItemCategory(
      {required String businessId, required String categoryId}) async {
    await _dio
        .delete<void>('/v1/businesses/$businessId/item-categories/$categoryId');
  }

  Future<List<Map<String, dynamic>>> listCategoryTypes({
    required String businessId,
    required String categoryId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/item-categories/$categoryId/category-types',
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createCategoryType({
    required String businessId,
    required String categoryId,
    required String name,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId/category-types',
      data: {'name': name},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateCategoryType({
    required String businessId,
    required String categoryId,
    required String typeId,
    required String name,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId/category-types/$typeId',
      data: {'name': name},
    );
    return res.data ?? {};
  }

  Future<void> deleteCategoryType({
    required String businessId,
    required String categoryId,
    required String typeId,
  }) async {
    await _dio.delete<void>(
      '/v1/businesses/$businessId/item-categories/$categoryId/category-types/$typeId',
    );
  }

  Future<List<Map<String, dynamic>>> listCatalogItems({
    required String businessId,
    String? categoryId,
    String? typeId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/catalog-items',
      queryParameters: {
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
        if (typeId != null && typeId.isNotEmpty) 'type_id': typeId,
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createCatalogItem({
    required String businessId,
    required String categoryId,
    required String name,
    required String defaultUnit,
    required List<String> defaultSupplierIds,
    String? hsnCode,
    String? itemCode,
    String? typeId,
    double? defaultKgPerBag,
    double? defaultItemsPerBox,
    double? defaultWeightPerTin,
    String? defaultPurchaseUnit,
    String? defaultSaleUnit,
    double? taxPercent,
    double? defaultLandingCost,
    double? defaultSellingCost,
    List<String> defaultBrokerIds = const [],
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items',
      data: {
        'category_id': categoryId,
        'name': name,
        'default_unit': defaultUnit,
        'default_supplier_ids': defaultSupplierIds,
        if (defaultBrokerIds.isNotEmpty) 'default_broker_ids': defaultBrokerIds,
        if (hsnCode != null && hsnCode.trim().isNotEmpty) 'hsn_code': hsnCode.trim(),
        if (itemCode != null && itemCode.trim().isNotEmpty) 'item_code': itemCode.trim(),
        if (typeId != null && typeId.isNotEmpty) 'type_id': typeId,
        if (defaultKgPerBag != null && defaultKgPerBag > 0)
          'default_kg_per_bag': defaultKgPerBag,
        if (defaultItemsPerBox != null && defaultItemsPerBox > 0)
          'default_items_per_box': defaultItemsPerBox,
        if (defaultWeightPerTin != null && defaultWeightPerTin > 0)
          'default_weight_per_tin': defaultWeightPerTin,
        if (defaultPurchaseUnit != null && defaultPurchaseUnit.isNotEmpty)
          'default_purchase_unit': defaultPurchaseUnit,
        if (defaultSaleUnit != null && defaultSaleUnit.isNotEmpty)
          'default_sale_unit': defaultSaleUnit,
        if (taxPercent != null) 'tax_percent': taxPercent,
        if (defaultLandingCost != null) 'default_landing_cost': defaultLandingCost,
        if (defaultSellingCost != null) 'default_selling_cost': defaultSellingCost,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> supplierPurchaseDefaults({
    required String businessId,
    required String supplierId,
    required String itemId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/supplier-purchase-defaults',
      queryParameters: {'supplier_id': supplierId},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> getCatalogItem(
      {required String businessId, required String itemId}) async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/v1/businesses/$businessId/catalog-items/$itemId');
    return res.data ?? {};
  }

  /// Trade purchases only: latest price per supplier, last five landed prices, avg.
  Future<Map<String, dynamic>> catalogItemTradeSupplierPrices({
    required String businessId,
    required String itemId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/trade-supplier-prices',
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateCatalogItem({
    required String businessId,
    required String itemId,
    String? categoryId,
    String? typeId,
    bool patchTypeId = false,
    String? name,
    String? defaultUnit,
    bool includeDefaultUnit = false,
    bool patchDefaultKgPerBag = false,
    double? defaultKgPerBag,
    bool patchDefaultItemsPerBox = false,
    double? defaultItemsPerBox,
    bool patchDefaultWeightPerTin = false,
    double? defaultWeightPerTin,
    String? defaultPurchaseUnit,
    String? defaultSaleUnit,
    String? hsnCode,
    double? taxPercent,
    double? defaultLandingCost,
    double? defaultSellingCost,
    List<String>? defaultSupplierIds,
    List<String>? defaultBrokerIds,
  }) async {
    final data = <String, dynamic>{
      if (categoryId != null) 'category_id': categoryId,
      if (patchTypeId) 'type_id': typeId,
      if (name != null) 'name': name,
    };
    if (includeDefaultUnit) {
      data['default_unit'] = defaultUnit;
    } else if (defaultUnit != null) {
      data['default_unit'] = defaultUnit;
    }
    if (patchDefaultKgPerBag) {
      data['default_kg_per_bag'] = defaultKgPerBag;
    }
    if (patchDefaultItemsPerBox) {
      data['default_items_per_box'] = defaultItemsPerBox;
    }
    if (patchDefaultWeightPerTin) {
      data['default_weight_per_tin'] = defaultWeightPerTin;
    }
    if (defaultPurchaseUnit != null) {
      data['default_purchase_unit'] = defaultPurchaseUnit;
    }
    if (defaultSaleUnit != null) {
      data['default_sale_unit'] = defaultSaleUnit;
    }
    if (hsnCode != null) {
      data['hsn_code'] = hsnCode.isEmpty ? null : hsnCode;
    }
    if (taxPercent != null) {
      data['tax_percent'] = taxPercent;
    }
    if (defaultLandingCost != null) {
      data['default_landing_cost'] = defaultLandingCost;
    }
    if (defaultSellingCost != null) {
      data['default_selling_cost'] = defaultSellingCost;
    }
    if (defaultSupplierIds != null) {
      data['default_supplier_ids'] = defaultSupplierIds;
    }
    if (defaultBrokerIds != null) {
      data['default_broker_ids'] = defaultBrokerIds;
    }
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId',
      data: data,
    );
    return res.data ?? {};
  }

  Future<void> deleteCatalogItem(
      {required String businessId, required String itemId}) async {
    await _dio.delete<void>('/v1/businesses/$businessId/catalog-items/$itemId');
  }

  Future<Map<String, dynamic>> catalogItemInsights({
    required String businessId,
    required String itemId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/insights',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> categoryInsights({
    required String businessId,
    required String categoryId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/item-categories/$categoryId/insights',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> catalogItemLines({
    required String businessId,
    required String itemId,
    required String from,
    required String to,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/catalog-items/$itemId/lines',
      queryParameters: {
        'from': from,
        'to': to,
        'limit': limit,
        'offset': offset,
      },
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> listCatalogVariants({
    required String businessId,
    required String itemId,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        '/v1/businesses/$businessId/catalog-items/$itemId/variants',
      );
      final data = res.data;
      if (data is! List) return [];
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on DioException catch (e) {
      // Current server returns 200 (maybe empty). A 404 here usually means the
      // running API is older than this client (route not registered) — treat as no variants.
      if (e.response?.statusCode == 404) return [];
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createCatalogVariant({
    required String businessId,
    required String itemId,
    required String name,
    double? defaultKgPerBag,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/variants',
      data: {
        'name': name,
        if (defaultKgPerBag != null) 'default_kg_per_bag': defaultKgPerBag,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> updateCatalogVariant({
    required String businessId,
    required String variantId,
    String? name,
    double? defaultKgPerBag,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-variants/$variantId',
      data: {
        if (name != null) 'name': name,
        if (defaultKgPerBag != null) 'default_kg_per_bag': defaultKgPerBag,
      },
    );
    return res.data ?? {};
  }

  Future<void> deleteCatalogVariant(
      {required String businessId, required String variantId}) async {
    await _dio
        .delete<void>('/v1/businesses/$businessId/catalog-variants/$variantId');
  }

  Future<Map<String, dynamic>> contactsSearch(
      {required String businessId, required String query}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/contacts/search',
      queryParameters: {'q': query},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> supplierMetrics({
    required String businessId,
    required String supplierId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers/$supplierId/metrics',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> brokerMetrics({
    required String businessId,
    required String brokerId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers/$brokerId/metrics',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> categoryItems({
    required String businessId,
    required String category,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/contacts/category-items',
      queryParameters: {'category': category, 'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Legacy entry-based home KPIs (top item profit, MTD vs prior month, alerts).
  Future<Map<String, dynamic>> homeInsights({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/insights',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> analyticsItems(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/items',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsCategories(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/categories',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsSuppliers(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/suppliers',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Per-supplier item breakdown (for expandable supplier rows in Reports).
  Future<List<Map<String, dynamic>>> analyticsSupplierItems({
    required String businessId,
    required String supplierId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/suppliers/$supplierId/items',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsBrokers(
      {required String businessId,
      required String from,
      required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/brokers',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> priceIntelligence({
    required String businessId,
    required String item,
    double? currentPrice,
    int windowDays = 90,
    String priceField = 'landing',
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/price-intelligence',
      queryParameters: {
        'item': item,
        if (currentPrice != null) 'current_price': currentPrice,
        'window_days': windowDays,
        'price_field': priceField,
      },
    );
    return res.data ?? {};
  }

  /// OCR preview stub — requires `ENABLE_OCR` on server; never auto-saves.
  Future<Map<String, dynamic>> mediaOcrPreview({
    required String businessId,
    String imageBase64 = '',
    String? pasteText,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/media/ocr',
      data: {
        'image_base64': imageBase64,
        if (pasteText != null && pasteText.trim().isNotEmpty) 'paste_text': pasteText.trim(),
      },
    );
    return res.data ?? {};
  }

  /// Voice/STT preview stub — requires `ENABLE_VOICE` on server; never auto-saves.
  Future<Map<String, dynamic>> mediaVoicePreview(
      {required String businessId, String audioBase64 = 'QQ=='}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/media/voice',
      data: {'audio_base64': audioBase64},
    );
    return res.data ?? {};
  }

  /// In-app assistant — preview → confirm; optional [previewToken] + [entryDraft] for YES/NO.
  ///
  /// Uses a longer receive timeout (LLM cold start) and retries transient network / gateway errors.
  Future<Map<String, dynamic>> aiChat({
    required String businessId,
    required List<Map<String, dynamic>> messages,
    String? previewToken,
    Map<String, dynamic>? entryDraft,
  }) async {
    final path = '/v1/businesses/$businessId/ai/chat';
    final data = <String, dynamic>{
      'messages': messages,
      if (previewToken != null) 'preview_token': previewToken,
      if (entryDraft != null) 'entry_draft': entryDraft,
    };
    const receive = Duration(seconds: 120);
    const maxAttempts = 3;
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final res = await _dio.post<Map<String, dynamic>>(
          path,
          data: data,
          options: Options(receiveTimeout: receive),
        );
        return res.data ?? {};
      } on DioException catch (e) {
        lastError = e;
        final canRetry = attempt < maxAttempts - 1 && _retryableAssistantRequest(e);
        if (!canRetry) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 320 * (attempt + 1)));
      }
    }
    throw lastError ?? StateError('aiChat: no attempt');
  }

  /// Structured intent JSON (server-side; increments usage counter when AI enabled).
  Future<Map<String, dynamic>> aiIntent({
    required String businessId,
    required String text,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/ai/intent',
      data: {'text': text},
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> billingStatus(
      {required String businessId}) async {
    final res = await _dio
        .get<Map<String, dynamic>>('/v1/businesses/$businessId/billing/status');
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> billingQuote({
    required String businessId,
    String planCode = 'basic',
    bool whatsappAddon = false,
    bool aiAddon = false,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/billing/quote',
      queryParameters: {
        'plan_code': planCode,
        'whatsapp_addon': whatsappAddon,
        'ai_addon': aiAddon,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> billingCreateOrder({
    required String businessId,
    String planCode = 'basic',
    bool whatsappAddon = false,
    bool aiAddon = false,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/billing/create-order',
      data: {
        'plan_code': planCode,
        'whatsapp_addon': whatsappAddon,
        'ai_addon': aiAddon,
      },
    );
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> billingVerify({
    required String businessId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/billing/verify',
      data: {
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      },
    );
    return res.data ?? {};
  }

  /// Monthly cloud / infra line (Settings + Home card).
  Future<Map<String, dynamic>> getCloudCost({required String businessId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/cloud-cost');
    final d = res.data;
    if (d is! Map) return {};
    return Map<String, dynamic>.from(d);
  }

  Future<Map<String, dynamic>> patchCloudCost({
    required String businessId,
    String? name,
    double? amountInr,
    int? dueDay,
  }) async {
    final res = await _dio.patch<dynamic>(
      '/v1/businesses/$businessId/cloud-cost',
      data: {
        if (name != null) 'name': name,
        if (amountInr != null) 'amount_inr': amountInr,
        if (dueDay != null) 'due_day': dueDay,
      },
    );
    final d = res.data;
    if (d is! Map) return {};
    return Map<String, dynamic>.from(d);
  }

  Future<Map<String, dynamic>> postCloudCostPay({
    required String businessId,
    double? amountInr,
    String? paymentId,
    String? provider,
  }) async {
    final res = await _dio.post<dynamic>(
      '/v1/businesses/$businessId/cloud-cost/pay',
      data: {
        if (amountInr != null) 'amount_inr': amountInr,
        if (paymentId != null && paymentId.isNotEmpty) 'payment_id': paymentId,
        if (provider != null && provider.isNotEmpty) 'provider': provider,
      },
    );
    final d = res.data;
    if (d is! Map) return {};
    return Map<String, dynamic>.from(d);
  }
}
