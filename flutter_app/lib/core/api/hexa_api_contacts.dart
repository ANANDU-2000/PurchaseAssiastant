part of 'hexa_api.dart';

mixin HexaApiContactsMethods on HexaApiBase {

  Future<List<Map<String, dynamic>>> listSuppliers({
    required String businessId,

    /// Smaller JSON (no address/notes); server skips loading those columns.
    bool compact = true,

    /// Only honored when [compact] is true (server cap 5000).
    int? limit,
  }) async {
    final q = <String, dynamic>{};
    if (compact) q['compact'] = 'true';
    if (compact && limit != null) q['limit'] = limit;
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/suppliers',
      queryParameters: q.isEmpty ? null : q,
    );
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
      if (location != null && location.isNotEmpty) 'location': location,
      if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      if (brokerIds != null && brokerIds.isNotEmpty) 'broker_ids': brokerIds,
      if (gstNumber != null && gstNumber.isNotEmpty) 'gst_number': gstNumber,
      if (address != null && address.isNotEmpty) 'address': address,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      if (defaultPaymentDays != null)
        'default_payment_days': defaultPaymentDays,
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
    return res.data ?? <String, dynamic>{};
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
    return <String, dynamic>{};
  }


  Future<Map<String, dynamic>> getBroker(
      {required String businessId, required String brokerId}) async {
    final res =
        await _dio.get<dynamic>('/v1/businesses/$businessId/brokers/$brokerId');
    final d = res.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return <String, dynamic>{};
  }


  Future<List<Map<String, dynamic>>> listBrokerLinkedSuppliers({
    required String businessId,
    required String brokerId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/brokers/$brokerId/linked-suppliers',
    );
    final data = res.data;
    if (data is! List) return [];
    return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }


  Future<Map<String, dynamic>> createBroker({
    required String businessId,
    required String name,
    String? phone,
    String? location,
    String? notes,
    String commissionType = 'percent',
    double? commissionValue,
    int? defaultPaymentDays,
    double? defaultDiscount,
    double? defaultDeliveredRate,
    double? defaultBilltyRate,
    String? freightType,
    List<String>? supplierIds,
    Map<String, dynamic>? preferences,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers',
      data: {
        'name': name,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        if (location != null && location.isNotEmpty) 'location': location,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
        'commission_type': commissionType,
        if (commissionValue != null) 'commission_value': commissionValue,
        if (defaultPaymentDays != null)
          'default_payment_days': defaultPaymentDays,
        if (defaultDiscount != null) 'default_discount': defaultDiscount,
        if (defaultDeliveredRate != null)
          'default_delivered_rate': defaultDeliveredRate,
        if (defaultBilltyRate != null) 'default_billty_rate': defaultBilltyRate,
        if (freightType != null && freightType.isNotEmpty)
          'freight_type': freightType,
        if (supplierIds != null) 'supplier_ids': supplierIds,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return res.data ?? <String, dynamic>{};
  }


  Future<Map<String, dynamic>> updateSupplier({
    required String businessId,
    required String supplierId,
    String? name,
    String? phone,
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
    return res.data ?? <String, dynamic>{};
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
    String? location,
    String? notes,
    String? commissionType,
    double? commissionValue,
    int? defaultPaymentDays,
    double? defaultDiscount,
    double? defaultDeliveredRate,
    double? defaultBilltyRate,
    String? freightType,
    List<String>? supplierIds,
    Map<String, dynamic>? preferences,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/brokers/$brokerId',
      data: {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (location != null) 'location': location,
        if (notes != null) 'notes': notes,
        if (commissionType != null) 'commission_type': commissionType,
        if (commissionValue != null) 'commission_value': commissionValue,
        if (defaultPaymentDays != null)
          'default_payment_days': defaultPaymentDays,
        if (defaultDiscount != null) 'default_discount': defaultDiscount,
        if (defaultDeliveredRate != null)
          'default_delivered_rate': defaultDeliveredRate,
        if (defaultBilltyRate != null) 'default_billty_rate': defaultBilltyRate,
        if (freightType != null) 'freight_type': freightType,
        if (supplierIds != null) 'supplier_ids': supplierIds,
        if (preferences != null) 'preferences': preferences,
      },
    );
    return res.data ?? <String, dynamic>{};
  }


  Future<void> deleteBroker(
      {required String businessId, required String brokerId}) async {
    await _dio.delete<void>('/v1/businesses/$businessId/brokers/$brokerId');
  }


  /// Trade purchases only: latest price per supplier, last five landed prices, avg.
  Future<Map<String, dynamic>> catalogItemTradeSupplierPrices({
    required String businessId,
    required String itemId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/catalog-items/$itemId/trade-supplier-prices',
    );
    return res.data ?? <String, dynamic>{};
  }


  Future<Map<String, dynamic>> contactsSearch({
    required String businessId,
    required String query,
    String? scope,
  }) async {
    final qp = <String, dynamic>{'q': query};
    if (scope != null && scope.trim().isNotEmpty) {
      qp['scope'] = scope.trim();
    }
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/contacts/search',
      queryParameters: qp,
    );
    return res.data ?? <String, dynamic>{};
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
    return res.data ?? <String, dynamic>{};
  }

}
