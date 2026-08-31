part of 'hexa_api.dart';

mixin HexaApiPurchaseMethods on HexaApiBase {

  /// GET `/trade-purchases` caps `limit` at 50; larger values are fetched in pages.
  static const int _kTradePurchasesApiMaxLimit = 50;


  Future<List<Map<String, dynamic>>> _listTradePurchasesPage({
    required String businessId,
    required int limit,
    required int offset,
    String? statusParam,
    String? q,
    String? supplierId,
    String? brokerId,
    String? catalogItemId,
    String? purchaseFrom,
    String? purchaseTo,
    bool includeLines = false,
  }) async {
    final path = '/v1/businesses/$businessId/trade-purchases';
    final queryParameters = <String, dynamic>{
      'limit': limit,
      'offset': offset,
      'include_lines': includeLines,
      if (statusParam != null) 'status': statusParam,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      if (supplierId != null && supplierId.trim().isNotEmpty)
        'supplier_id': supplierId.trim(),
      if (brokerId != null && brokerId.trim().isNotEmpty)
        'broker_id': brokerId.trim(),
      if (catalogItemId != null && catalogItemId.trim().isNotEmpty)
        'catalog_item_id': catalogItemId.trim(),
      if (purchaseFrom != null && purchaseFrom.isNotEmpty)
        'purchase_from': purchaseFrom,
      if (purchaseTo != null && purchaseTo.isNotEmpty)
        'purchase_to': purchaseTo,
    };

    if (kDebugMode) {
      debugPrint('HexaApi.listTradePurchases GET $path query=$queryParameters');
    }

    try {
      final res =
          await _dio.get<dynamic>(path, queryParameters: queryParameters);
      if (kDebugMode) {
        debugPrint('HexaApi.listTradePurchases status=${res.statusCode}');
      }
      final data = res.data;
      if (data is! List) return [];
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        if (kDebugMode) {
          debugPrint(
            'HexaApi.listTradePurchases 422 → [] (break poisoned-filter loops)',
          );
        }
        return [];
      }
      rethrow;
    }
  }

  /// Trade purchases (wholesale PUR-YYYY-XXXX flow).

  /// Trade purchases (wholesale PUR-YYYY-XXXX flow).
  Future<List<Map<String, dynamic>>> listTradePurchases({
    required String businessId,
    int limit = 20,
    int offset = 0,
    String? status,
    String? q,
    String? supplierId,
    String? brokerId,
    String? catalogItemId,
    String? purchaseFrom,
    String? purchaseTo,
    bool includeLines = false,
  }) async {
    final s = status?.trim().toLowerCase();
    final statusNorm = (s == null ||
            s.isEmpty ||
            s == 'all' ||
            s == 'undefined' ||
            s == 'null')
        ? null
        : s;
    const allowed = {'draft', 'due_soon', 'overdue', 'paid'};
    final statusParam =
        statusNorm != null && allowed.contains(statusNorm) ? statusNorm : null;

    final want = limit < 1 ? 1 : limit;
    var remaining = want;
    var nextOffset = offset;
    final out = <Map<String, dynamic>>[];

    while (remaining > 0) {
      final pageSize = min(remaining, _kTradePurchasesApiMaxLimit);
      final page = await _listTradePurchasesPage(
        businessId: businessId,
        limit: pageSize,
        offset: nextOffset,
        statusParam: statusParam,
        q: q,
        supplierId: supplierId,
        brokerId: brokerId,
        catalogItemId: catalogItemId,
        purchaseFrom: purchaseFrom,
        purchaseTo: purchaseTo,
        includeLines: includeLines,
      );
      if (page.isEmpty) break;
      out.addAll(page);
      if (page.length < pageSize) break;
      nextOffset += page.length;
      remaining -= page.length;
    }
    return out;
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
      if (e.response?.statusCode == 404) return <String, dynamic>{};
      // Draft is optional UX convenience — avoid hard failures when API is
      // temporarily unreachable or slow.
      if (e.response == null) return <String, dynamic>{};
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
    return res.data ?? <String, dynamic>{};
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
    return res.data ?? <String, dynamic>{};
  }

  /// SSOT line + header totals (non-mutating). Same math as create/persist.

  /// SSOT line + header totals (non-mutating). Same math as create/persist.
  Future<Map<String, dynamic>> previewTradePurchaseLines({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/preview-lines',
      data: body,
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
  }

  /// Full create validation without persisting (`ok` + `errors` + `warnings`).

  /// Full create validation without persisting (`ok` + `errors` + `warnings`).
  Future<Map<String, dynamic>> validateTradePurchase({
    required String businessId,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/validate',
      data: body,
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
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
    return <String, dynamic>{};
  }


  Future<Map<String, dynamic>> getTradePurchase({
    required String businessId,
    required String purchaseId,
    bool failFast = false,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId',
      options: failFast
          ? Options(extra: const {'skipAutoRetry': true})
          : null,
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
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
    return <String, dynamic>{};
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
        'paid_amount': StrictDecimal.fromObject(paidAmount).format(2),
        if (paidAtIso != null && paidAtIso.isNotEmpty) 'paid_at': paidAtIso,
      },
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
  }


  Future<Map<String, dynamic>> fetchDeliveryPipeline({
    required String businessId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/delivery-pipeline',
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
  }


  Future<Map<String, dynamic>> dispatchPurchase({
    required String businessId,
    required String purchaseId,
    String? truckNumber,
    String? driverContact,
    String? dispatchNote,
    bool markInTransit = false,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/dispatch',
      data: {
        if (truckNumber != null && truckNumber.isNotEmpty)
          'truck_number': truckNumber,
        if (driverContact != null && driverContact.isNotEmpty)
          'driver_contact': driverContact,
        if (dispatchNote != null && dispatchNote.isNotEmpty)
          'dispatch_note': dispatchNote,
        'mark_in_transit': markInTransit,
      },
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
  }


  Future<Map<String, dynamic>> arrivePurchase({
    required String businessId,
    required String purchaseId,
    String? notes,
    String? truckNumber,
    String? driverContact,
    double? damageQty,
    double? missingQty,
    bool? brokerConfirmed,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/arrive',
      data: {
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        if (truckNumber != null && truckNumber.trim().isNotEmpty)
          'truck_number': truckNumber.trim(),
        if (driverContact != null && driverContact.trim().isNotEmpty)
          'driver_contact': driverContact.trim(),
        if (damageQty != null && damageQty > 0) 'damage_qty': damageQty,
        if (missingQty != null && missingQty > 0) 'missing_qty': missingQty,
        if (brokerConfirmed == true) 'broker_confirmed': true,
      },
      options: _stockWriteOptions,
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
  }


  Future<Map<String, dynamic>> commitPurchaseDelivery({
    required String businessId,
    required String purchaseId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/commit-stock',
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
  }

  /// Marks delivery pending (reverts stock when previously committed).

  /// Marks delivery pending (reverts stock when previously committed).
  Future<Map<String, dynamic>> markPurchaseDelivered({
    required String businessId,
    required String purchaseId,
    required bool isDelivered,
    String? deliveryNotes,
  }) async {
    final path =
        '/v1/businesses/$businessId/trade-purchases/$purchaseId/delivery';
    final resp = await _dio.patch<dynamic>(
      path,
      data: {
        'is_delivered': isDelivered,
        if (deliveryNotes != null && deliveryNotes.isNotEmpty)
          'delivery_notes': deliveryNotes,
        if (isDelivered) 'delivered_at': DateTime.now().toIso8601String(),
      },
    );
    final d = resp.data;
    if (d is Map) return Map<String, dynamic>.from(d);
    return <String, dynamic>{};
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
        if (paidAmount != null)
          'paid_amount': StrictDecimal.fromObject(paidAmount).format(2),
        if (paidAtIso != null && paidAtIso.isNotEmpty) 'paid_at': paidAtIso,
      },
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
  }


  Future<Map<String, dynamic>> lastTradePurchaseDefaults({
    required String businessId,
    required String catalogItemId,
    String? supplierId,
    String? brokerId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/last-defaults',
      queryParameters: {
        'catalog_item_id': catalogItemId,
        if (supplierId != null && supplierId.isNotEmpty)
          'supplier_id': supplierId,
        if (brokerId != null && brokerId.isNotEmpty) 'broker_id': brokerId,
      },
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
  }


  Future<Map<String, dynamic>> cancelPurchase({
    required String businessId,
    required String purchaseId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/cancel',
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
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
    int? tzOffsetMinutes,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-summary',
      queryParameters: {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
        if (tzOffsetMinutes != null)
          'tz_offset_minutes': tzOffsetMinutes.toString(),
        if (supplierId != null && supplierId.isNotEmpty)
          'supplier_id': supplierId,
      },
    );
    return res.data ?? {};
  }


  Future<Map<String, dynamic>> verifyPurchaseDelivery({
    required String businessId,
    required String purchaseId,
    required List<Map<String, dynamic>> lines,
    String? notes,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/verify',
      data: {
        'lines': lines,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
      options: _stockWriteOptions,
    );
    return res.data ?? {};
  }


  Future<Map<String, dynamic>> createPurchaseDamageReport({
    required String businessId,
    required String purchaseId,
    required double qtyDamaged,
    String? itemName,
    String? damageType,
    String? catalogItemId,
    String? unit,
    String? reason,
    String? photoUrl,
    String? notes,
    bool emitNotification = true,
    int? damagedItemsInBatch,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/damage-reports',
      data: {
        if (itemName != null && itemName.trim().isNotEmpty)
          'item_name': itemName.trim(),
        'qty_damaged': qtyDamaged,
        if (damageType != null && damageType.isNotEmpty)
          'damage_type': damageType,
        if (catalogItemId != null && catalogItemId.isNotEmpty)
          'catalog_item_id': catalogItemId,
        if (unit != null && unit.trim().isNotEmpty) 'unit': unit.trim(),
        if (reason != null && reason.isNotEmpty) 'reason': reason,
        if (photoUrl != null && photoUrl.trim().isNotEmpty)
          'photo_url': photoUrl.trim(),
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        'emit_notification': emitNotification,
        if (damagedItemsInBatch != null && damagedItemsInBatch > 0)
          'damaged_items_in_batch': damagedItemsInBatch,
      },
    );
    return res.data ?? {};
  }


  Future<Map<String, dynamic>> patchPurchaseDamageReportStatus({
    required String businessId,
    required String reportId,
    required String status,
    String? notes,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/v1/businesses/$businessId/damage-reports/$reportId',
      data: {
        'status': status,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
    return res.data ?? {};
  }


  Future<int> getPendingDamageReportsCount({
    required String businessId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/damage-reports/pending-count',
    );
    return coerceToInt(res.data?['count']);
  }


  Future<List<Map<String, dynamic>>> listPurchaseDamageReports({
    required String businessId,
    required String purchaseId,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/trade-purchases/$purchaseId/damage-reports',
    );
    return _parseJsonMapList(res.data);
  }

  /// Trade purchase line aggregates (replaces legacy Entry-based `/analytics/items`).

  /// Latest [TradePurchase] header for [supplierId] (strict DB autofill — no aggregates).
  Future<Map<String, dynamic>> tradeLastSupplierAutofill({
    required String businessId,
    required String supplierId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/trade-last-supplier-autofill',
      queryParameters: {'supplier_id': supplierId},
    );
    return Map<String, dynamic>.from(res.data ?? <String, dynamic>{});
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


  Future<Map<String, dynamic>> getItemPurchaseIntelligence({
    required String businessId,
    required String itemId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/stock/items/$itemId/purchase-intelligence',
    );
    return res.data ?? {};
  }

}
