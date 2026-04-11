import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../models/session.dart';

class HexaApi {
  HexaApi({String? baseUrl}) : _dio = Dio(BaseOptions(baseUrl: baseUrl ?? AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 30)));

  final Dio _dio;

  Dio get raw => _dio;

  void setAuthToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('Authorization');
    } else {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
  }

  ({String access, String refresh}) _tokenPairFromResponse(Response<Map<String, dynamic>> res) {
    final d = res.data!;
    return (access: d['access_token'] as String, refresh: d['refresh_token'] as String);
  }

  Future<({String access, String refresh})> login({required String emailOrUsername, required String password}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/login',
      data: {'email_or_username': emailOrUsername, 'password': password},
    );
    return _tokenPairFromResponse(res);
  }

  Future<({String access, String refresh})> register({
    required String username,
    required String email,
    required String password,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/register',
      data: {'username': username, 'email': email, 'password': password},
    );
    return _tokenPairFromResponse(res);
  }

  Future<({String access, String refresh})> loginWithGoogle({required String idToken}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/auth/google',
      data: {'id_token': idToken},
    );
    return _tokenPairFromResponse(res);
  }

  Future<List<BusinessBrief>> meBusinesses() async {
    final res = await _dio.get<dynamic>('/v1/me/businesses');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => BusinessBrief.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Future<Map<String, dynamic>> analyticsSummary({required String businessId, required String from, required String to}) async {
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
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/entries',
      queryParameters: {
        if (from != null) 'from': from,
        if (to != null) 'to': to,
        if (item != null && item.isNotEmpty) 'item': item,
        if (supplierId != null && supplierId.isNotEmpty) 'supplier_id': supplierId,
      },
    );
    final items = res.data?['items'];
    if (items is List) return items;
    return [];
  }

  Future<Map<String, dynamic>> getEntry({required String businessId, required String entryId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/entries/$entryId');
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  /// Preview (`confirm: false`) returns 200 with `preview: true`. Confirm returns 201.
  Future<Map<String, dynamic>> createEntry({required String businessId, required Map<String, dynamic> body}) async {
    final res = await _dio.post<dynamic>('/v1/businesses/$businessId/entries', data: body);
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> checkDuplicate({
    required String businessId,
    required String itemName,
    required double qty,
    required String entryDateIso,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/entries/check-duplicate',
      data: {'item_name': itemName, 'qty': qty, 'entry_date': entryDateIso},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> listSuppliers({required String businessId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/suppliers');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> createSupplier({
    required String businessId,
    required String name,
    String? phone,
    String? location,
    String? brokerId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers',
      data: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (location != null && location.isNotEmpty) 'location': location,
        if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      },
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> listBrokers({required String businessId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/brokers');
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<Map<String, dynamic>> getSupplier({required String businessId, required String supplierId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/suppliers/$supplierId');
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  Future<Map<String, dynamic>> getBroker({required String businessId, required String brokerId}) async {
    final res = await _dio.get<dynamic>('/v1/businesses/$businessId/brokers/$brokerId');
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
    String? location,
    String? brokerId,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/suppliers/$supplierId',
      data: {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (location != null) 'location': location,
        if (brokerId != null) 'broker_id': brokerId,
      },
    );
    return res.data ?? {};
  }

  Future<void> deleteSupplier({required String businessId, required String supplierId}) async {
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

  Future<void> deleteBroker({required String businessId, required String brokerId}) async {
    await _dio.delete<void>('/v1/businesses/$businessId/brokers/$brokerId');
  }

  Future<Map<String, dynamic>> contactsSearch({required String businessId, required String query}) async {
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

  Future<Map<String, dynamic>> homeInsights({required String businessId, required String from, required String to}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/analytics/insights',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }

  Future<List<Map<String, dynamic>>> analyticsItems({required String businessId, required String from, required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/items',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsCategories({required String businessId, required String from, required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/categories',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsSuppliers({required String businessId, required String from, required String to}) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/analytics/suppliers',
      queryParameters: {'from': from, 'to': to},
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> analyticsBrokers({required String businessId, required String from, required String to}) async {
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
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/price-intelligence',
      queryParameters: {
        'item': item,
        if (currentPrice != null) 'current_price': currentPrice,
        'window_days': windowDays,
      },
    );
    return res.data ?? {};
  }

  /// OCR preview stub — requires `ENABLE_OCR` on server; never auto-saves.
  Future<Map<String, dynamic>> mediaOcrPreview({required String businessId, String imageBase64 = 'QQ=='}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/media/ocr',
      data: {'image_base64': imageBase64},
    );
    return res.data ?? {};
  }

  /// Voice/STT preview stub — requires `ENABLE_VOICE` on server; never auto-saves.
  Future<Map<String, dynamic>> mediaVoicePreview({required String businessId, String audioBase64 = 'QQ=='}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/media/voice',
      data: {'audio_base64': audioBase64},
    );
    return res.data ?? {};
  }
}
