import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

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

class HexaApi {
  HexaApi({String? baseUrl, Future<bool> Function()? onUnauthorizedRefresh})
      : _onUnauthorizedRefresh = onUnauthorizedRefresh,
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
        onError: (DioException err, ErrorInterceptorHandler handler) async {
          if (err.response?.statusCode != 401) {
            return handler.next(err);
          }
          final req = err.requestOptions;
          if (req.extra['authRetried'] == true) {
            return handler.next(err);
          }
          final path = req.uri.path;
          if (path.contains('/auth/login') ||
              path.contains('/auth/register') ||
              path.contains('/auth/google') ||
              path.contains('/auth/refresh')) {
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
  }

  final Dio _dio;
  final Dio _plain;
  final Future<bool> Function()? _onUnauthorizedRefresh;

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

  /// Owner: optional in-app title + logo URL (HTTPS recommended).
  Future<Map<String, dynamic>> patchBusinessBranding({
    required String businessId,
    String? brandingTitle,
    String? brandingLogoUrl,
    String? gstNumber,
    String? address,
    String? phone,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/me/businesses/$businessId/branding',
      data: {
        if (brandingTitle != null) 'branding_title': brandingTitle,
        if (brandingLogoUrl != null) 'branding_logo_url': brandingLogoUrl,
        if (gstNumber != null) 'gst_number': gstNumber,
        if (address != null) 'address': address,
        if (phone != null) 'phone': phone,
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

  Future<Map<String, dynamic>> analyticsInsights({
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

  Future<Map<String, dynamic>> getEntry(
      {required String businessId, required String entryId}) async {
    final res =
        await _dio.get<dynamic>('/v1/businesses/$businessId/entries/$entryId');
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  /// Preview (`confirm: false`) returns 200 with `preview: true`. Confirm returns 201.
  Future<Map<String, dynamic>> createEntry(
      {required String businessId, required Map<String, dynamic> body}) async {
    final res = await _dio.post<dynamic>('/v1/businesses/$businessId/entries',
        data: body);
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> checkDuplicate({
    required String businessId,
    required String itemName,
    required double qty,
    required String entryDateIso,
    String? supplierId,
    String? catalogVariantId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/entries/check-duplicate',
      data: {
        'item_name': itemName,
        'qty': qty,
        'entry_date': entryDateIso,
        if (supplierId != null && supplierId.isNotEmpty)
          'supplier_id': supplierId,
        if (catalogVariantId != null && catalogVariantId.isNotEmpty)
          'catalog_variant_id': catalogVariantId,
      },
    );
    return res.data ?? {};
  }

  /// Trade purchases (wholesale PUR-YYYY-XXXX flow).
  Future<List<Map<String, dynamic>>> listTradePurchases({
    required String businessId,
    int limit = 50,
    String status = 'all',
    String? q,
    String? supplierId,
    String? brokerId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/trade-purchases',
      queryParameters: {
        'limit': limit,
        'status': status,
        if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
        if (supplierId != null && supplierId.trim().isNotEmpty)
          'supplier_id': supplierId.trim(),
        if (brokerId != null && brokerId.trim().isNotEmpty) 'broker_id': brokerId.trim(),
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
    String? typeId,
    String? defaultUnit,
    double? defaultKgPerBag,
    String? defaultPurchaseUnit,
    String? defaultSaleUnit,
    String? hsnCode,
    double? taxPercent,
    double? defaultLandingCost,
    double? defaultSellingCost,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items',
      data: {
        'category_id': categoryId,
        'name': name,
        if (typeId != null && typeId.isNotEmpty) 'type_id': typeId,
        if (defaultUnit != null && defaultUnit.isNotEmpty)
          'default_unit': defaultUnit,
        if (defaultKgPerBag != null && defaultKgPerBag > 0)
          'default_kg_per_bag': defaultKgPerBag,
        if (defaultPurchaseUnit != null && defaultPurchaseUnit.isNotEmpty)
          'default_purchase_unit': defaultPurchaseUnit,
        if (defaultSaleUnit != null && defaultSaleUnit.isNotEmpty)
          'default_sale_unit': defaultSaleUnit,
        if (hsnCode != null && hsnCode.isNotEmpty) 'hsn_code': hsnCode,
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
    String? defaultPurchaseUnit,
    String? defaultSaleUnit,
    String? hsnCode,
    double? taxPercent,
    double? defaultLandingCost,
    double? defaultSellingCost,
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

  Future<Map<String, dynamic>> homeInsights(
      {required String businessId,
      required String from,
      required String to}) async {
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
}
