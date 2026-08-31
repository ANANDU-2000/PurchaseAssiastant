part of 'hexa_api.dart';

mixin HexaApiReportsMethods on HexaApiBase {

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

  /// Unified catalog items + suppliers + entries (server-side substring match).

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
    return _parseJsonMapList(res.data);
  }

  /// Catalog item snapshot + period purchase KPIs + paginated lines (reports drill-down).

  /// Catalog item snapshot + period purchase KPIs + paginated lines (reports drill-down).
  Future<Map<String, dynamic>> reportsItemBundle({
    required String businessId,
    required String catalogItemId,
    required String from,
    required String to,
    int limit = 80,
    int offset = 0,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/item/$catalogItemId',
      queryParameters: {
        'from': from,
        'to': to,
        'limit': limit,
        'offset': offset,
      },
    );
    return res.data ?? {};
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
    return _parseJsonMapList(res.data);
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
    return _parseJsonMapList(res.data);
  }

  /// Subcategory (CategoryType) spend — matches catalog category → type → items.

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
    return _parseJsonMapList(res.data);
  }


  Future<Map<String, dynamic>> tradeReportPeriodComparison({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/period-comparison',
      queryParameters: {'from': from, 'to': to},
    );
    return res.data ?? {};
  }


  Future<Map<String, dynamic>> tradeReportMovementSummary({
    required String businessId,
    required String from,
    required String to,
    int? tzOffsetMinutes,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/movement-summary',
      queryParameters: {
        'from': from,
        'to': to,
        if (tzOffsetMinutes != null)
          'tz_offset_minutes': tzOffsetMinutes.toString(),
      },
    );
    return res.data ?? {};
  }

  /// Per-day line profit sums (SSOT for overview charts; replaces listTradePurchases slicing).

  /// Per-day line profit sums (SSOT for overview charts; replaces listTradePurchases slicing).
  Future<List<Map<String, dynamic>>> tradeReportDailyProfit({
    required String businessId,
    required String from,
    required String to,
  }) async {
    final res = await _dio.get<dynamic>(
      '/v1/businesses/$businessId/reports/trade-daily-profit',
      queryParameters: {'from': from, 'to': to},
    );
    return _parseJsonMapList(res.data);
  }

  /// Bundled dashboard snapshot for home (`compact` omits heavy keys server-side).

  /// Bundled dashboard snapshot for home (`compact` omits heavy keys server-side).
  Future<Map<String, dynamic>> reportsHomeOverview({
    required String businessId,
    required String from,
    required String to,
    bool compact = false,
    bool shellBundle = false,
    int? maxSpanDays,
    int? tzOffsetMinutes,
    String? ifNoneMatch,
  }) async {
    final qp = <String, dynamic>{
      'from': from,
      'to': to,
      if (tzOffsetMinutes != null)
        'tz_offset_minutes': tzOffsetMinutes.toString(),
      if (compact) 'compact': true,
      if (shellBundle) 'shell_bundle': true,
      if (maxSpanDays != null) 'max_span_days': maxSpanDays,
    };
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/reports/home-overview',
      queryParameters: qp,
      options: Options(
        headers: {
          if (ifNoneMatch != null && ifNoneMatch.isNotEmpty)
            'If-None-Match': ifNoneMatch,
        },
        validateStatus: (code) => code != null && (code < 400 || code == 304),
      ),
    );
    if (res.statusCode == 304) {
      return const {'_not_modified': true};
    }
    final data = Map<String, dynamic>.from(res.data ?? {});
    final etag = res.headers.value('etag');
    if (etag != null && etag.isNotEmpty) {
      data['_etag'] = etag;
    }
    return data;
  }

  /// Per (item, supplier, broker) trade stats and best-supplier recommendations (deals≥2 vwap).

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

  /// Latest [TradePurchase] header for [supplierId] (strict DB autofill — no aggregates).

  Future<List<Map<String, dynamic>>> listReportSavedViews({
    required String businessId,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/v1/businesses/$businessId/report-views',
    );
    return (res.data ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }


  Future<Map<String, dynamic>> createReportSavedView({
    required String businessId,
    required String name,
    required String tab,
    required Map<String, dynamic> filtersJson,
    bool isDefault = false,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/businesses/$businessId/report-views',
      data: {
        'name': name,
        'tab': tab,
        'filters_json': filtersJson,
        'is_default': isDefault,
      },
    );
    return Map<String, dynamic>.from(res.data ?? {});
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
    try {
      final res = await _dio.get<dynamic>(
        '/v1/businesses/$businessId/price-intelligence',
        queryParameters: {
          'item': item,
          if (currentPrice != null) 'current_price': currentPrice,
          'window_days': windowDays,
          'price_field': priceField,
        },
      );
      final data = res.data;
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }
      return const <String, dynamic>{};
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const <String, dynamic>{};
      rethrow;
    }
  }


  Future<Map<String, dynamic>> getOperationalReports({
    required String businessId,
    int staleDays = 30,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/businesses/$businessId/operations/reports/summary',
      queryParameters: {'stale_days': staleDays},
    );
    return res.data ?? {};
  }

}
