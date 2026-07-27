import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import '../errors/user_facing_errors.dart';
import 'catalog_providers.dart';
import 'stock_list_exceptions.dart';
import 'stock_providers.dart';

Future<T> _fetchWithRetry<T>(Future<T> Function() load) async {
  for (var i = 0; i < 3; i++) {
    try {
      return await load();
    } catch (e, st) {
      if (e is StateError) rethrow;
      logSilencedApiError(e, st);
      if (i == 2) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 600 * (i + 1)));
    }
  }
  throw StateError('Unreachable');
}

bool _bundleEndpointUnavailable(Object error) {
  if (error is DioException) {
    final code = error.response?.statusCode;
    return code == 404 || code == 405 || code == 501;
  }
  return false;
}

Future<ItemDetailBundle> _fetchItemDetailFallback({
  required Ref ref,
  required String businessId,
  required String itemId,
}) async {
  final api = ref.read(hexaApiProvider);
  Object? catalogError;
  Map<String, dynamic> catalog = {};
  Object? stockError;
  Map<String, dynamic> stock = {};
  Object? activityError;
  Map<String, dynamic> activity = {};

  try {
    catalog = await api.getCatalogItem(businessId: businessId, itemId: itemId);
  } catch (e, st) {
    logSilencedApiError(e, st);
    catalogError = e;
  }
  try {
    stock = await api.getStockItem(businessId: businessId, itemId: itemId);
  } catch (e, st) {
    logSilencedApiError(e, st);
    stockError = e;
  }
  try {
    activity = await api.getStockItemActivity(
      businessId: businessId,
      itemId: itemId,
    );
  } catch (e, st) {
    logSilencedApiError(e, st);
    activityError = e;
  }

  return ItemDetailBundle(
    catalogItem: catalog,
    stockDetail: stock,
    activity: activity,
    tradePurchases: const [],
    catalogError: catalogError,
    stockError: stockError,
    activityError: activityError,
  );
}

class ItemDetailBundle {
  const ItemDetailBundle({
    required this.catalogItem,
    required this.stockDetail,
    required this.activity,
    required this.tradePurchases,
    this.catalogError,
    this.stockError,
    this.activityError,
  });

  final Map<String, dynamic> catalogItem;
  final Map<String, dynamic> stockDetail;
  final Map<String, dynamic> activity;
  final List<Map<String, dynamic>> tradePurchases;
  final Object? catalogError;
  final Object? stockError;
  final Object? activityError;

  bool get hasAnyData =>
      catalogItem.isNotEmpty ||
      stockDetail.isNotEmpty ||
      activity.isNotEmpty;

  bool get allSectionsFailed =>
      catalogError != null &&
      stockError != null &&
      activityError != null &&
      !hasAnyData;
}

const _emptyItemDetailBundle = ItemDetailBundle(
  catalogItem: {},
  stockDetail: {},
  activity: {},
  tradePurchases: [],
);

/// Bundled fetch for item detail warm-up (single API round-trip).
final itemDetailBundleProvider =
    FutureProvider.autoDispose.family<ItemDetailBundle, String>((ref, itemId) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));

  final session = ref.watch(sessionProvider);
  if (session == null) {
    return _emptyItemDetailBundle;
  }

  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) {
    return _emptyItemDetailBundle;
  }
  if (providerWasDisposed(disposed)) {
    return _emptyItemDetailBundle;
  }

  Object? catalogError;
  Map<String, dynamic> catalog = {};
  Object? stockError;
  Map<String, dynamic> stock = {};
  Object? activityError;
  Map<String, dynamic> activity = {};

  try {
    final raw = await _fetchWithRetry(
      () => ref.read(hexaApiProvider).getStockItemBundle(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          ),
    );
    if (providerWasDisposed(disposed)) {
      return _emptyItemDetailBundle;
    }
    final detail = raw['detail'];
    final catalogSnap = raw['catalog_snapshot'];
    final activityRaw = raw['activity'];
    if (detail is Map) {
      stock = Map<String, dynamic>.from(detail);
    }
    if (catalogSnap is Map) {
      catalog = Map<String, dynamic>.from(catalogSnap);
    }
    if (activityRaw is Map) {
      activity = Map<String, dynamic>.from(activityRaw);
    }
  } catch (e, st) {
    logSilencedApiError(e, st);
    if (_bundleEndpointUnavailable(e)) {
      return _fetchItemDetailFallback(
        ref: ref,
        businessId: session.primaryBusiness.id,
        itemId: itemId,
      );
    }
    catalogError = e;
    stockError = e;
    activityError = e;
  }

  if (providerWasDisposed(disposed)) {
    return _emptyItemDetailBundle;
  }

  return ItemDetailBundle(
    catalogItem: catalog,
    stockDetail: stock,
    activity: activity,
    tradePurchases: const [],
    catalogError: catalogError,
    stockError: stockError,
    activityError: activityError,
  );
});

/// Item analytics intelligence — fixed 30-day window (not tied to stock list query).
final itemStockIntelligenceProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
        (ref, itemId) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw const StockListFetchBlockedException('no_session');
  }
  await awaitProviderApiReady(ref);
  if (providerSkipApi(ref)) {
    throw const StockListFetchBlockedException('api_gate');
  }
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day);
  final start = end.subtract(const Duration(days: 29));
  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final result = await ref.read(hexaApiProvider).getStockIntelligence(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
        periodStart: iso(start),
        periodEnd: iso(end),
      );
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  return result;
});

/// Stock map for item detail sections — merges optimistic patches (no flash on save).
final itemDetailStockProvider =
    Provider.autoDispose.family<Map<String, dynamic>?, String>((ref, itemId) {
  final patch = ref.watch(stockItemDetailPatchProvider(itemId));
  final bundle = ref.watch(itemDetailBundleProvider(itemId)).valueOrNull;
  Map<String, dynamic>? base;
  if (bundle != null && bundle.stockDetail.isNotEmpty) {
    base = bundle.stockDetail;
  } else {
    base = ref.watch(stockItemDetailProvider(itemId)).valueOrNull;
  }
  if (patch.isEmpty) return base;
  if (base != null) return {...base, ...patch};
  return Map<String, dynamic>.from(patch);
});

/// Catalog map for item detail sections (leaf provider).
final itemDetailCatalogProvider =
    Provider.autoDispose.family<Map<String, dynamic>?, String>((ref, itemId) {
  final bundle = ref.watch(itemDetailBundleProvider(itemId)).valueOrNull;
  if (bundle != null && bundle.catalogItem.isNotEmpty) {
    return bundle.catalogItem;
  }
  return ref.watch(catalogItemDetailProvider(itemId)).valueOrNull;
});

/// Activity map for item detail timeline sections.
final itemDetailActivityProvider =
    Provider.autoDispose.family<Map<String, dynamic>?, String>((ref, itemId) {
  final bundle = ref.watch(itemDetailBundleProvider(itemId)).valueOrNull;
  if (bundle != null && bundle.activity.isNotEmpty) {
    return bundle.activity;
  }
  return ref.watch(stockItemActivityProvider(itemId)).valueOrNull;
});
