import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';
import '../models/session.dart';

class HexaApi {
  HexaApi({String? baseUrl, Future<bool> Function()? onUnauthorizedRefresh})
      : _onUnauthorizedRefresh = onUnauthorizedRefresh,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
          ),
        ),
        _plain = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? AppConfig.apiBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
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

  /// Assistant number hint for Settings (same gates as WhatsApp: linked account phone).
  Future<Map<String, dynamic>> getWhatsappAssistantInfo() async {
    final res = await _dio.get<Map<String, dynamic>>('/v1/me/whatsapp-assistant');
    return Map<String, dynamic>.from(res.data ?? {});
  }

  /// Owner: optional in-app title + logo URL (HTTPS recommended).
  Future<Map<String, dynamic>> patchBusinessBranding({
    required String businessId,
    String? brandingTitle,
    String? brandingLogoUrl,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/me/businesses/$businessId/branding',
      data: {
        if (brandingTitle != null) 'branding_title': brandingTitle,
        if (brandingLogoUrl != null) 'branding_logo_url': brandingLogoUrl,
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
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers',
      data: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (whatsappNumber != null && whatsappNumber.isNotEmpty)
          'whatsapp_number': whatsappNumber,
        if (location != null && location.isNotEmpty) 'location': location,
        if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      },
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
    String commissionType = 'percent',
    double? commissionValue,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers',
      data: {
        'name': name,
        'commission_type': commissionType,
        if (commissionValue != null) 'commission_value': commissionValue,
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
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers/$supplierId',
      data: {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (whatsappNumber != null) 'whatsapp_number': whatsappNumber,
        if (location != null) 'location': location,
        if (brokerId != null) 'broker_id': brokerId,
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
    String? commissionType,
    double? commissionValue,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers/$brokerId',
      data: {
        if (name != null) 'name': name,
        if (commissionType != null) 'commission_type': commissionType,
        if (commissionValue != null) 'commission_value': commissionValue,
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

  Future<List<Map<String, dynamic>>> listCatalogItems({
    required String businessId,
    String? categoryId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/catalog-items',
      queryParameters: {
        if (categoryId != null && categoryId.isNotEmpty)
          'category_id': categoryId,
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
    String? defaultUnit,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items',
      data: {
        'category_id': categoryId,
        'name': name,
        if (defaultUnit != null && defaultUnit.isNotEmpty)
          'default_unit': defaultUnit,
      },
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
    String? name,
    String? defaultUnit,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId',
      data: {
        if (categoryId != null) 'category_id': categoryId,
        if (name != null) 'name': name,
        if (defaultUnit != null) 'default_unit': defaultUnit,
      },
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
  Future<Map<String, dynamic>> mediaOcrPreview(
      {required String businessId, String imageBase64 = 'QQ=='}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/media/ocr',
      data: {'image_base64': imageBase64},
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

  /// Stub AI assistant — returns deterministic preview text; wire to LLM later.
  Future<Map<String, dynamic>> aiChat({
    required String businessId,
    required List<Map<String, dynamic>> messages,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/ai/chat',
      data: {'messages': messages},
    );
    return res.data ?? {};
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
