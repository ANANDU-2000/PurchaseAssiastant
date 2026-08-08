import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart';
import '../json_coerce.dart';
import 'stock_list_exceptions.dart';
import '../../features/stock/stock_list_row_patch.dart'
    show stockListPatchFromStockDetail;
import 'deferred_invalidation.dart';
import 'stock_list_providers.dart';

/// Item drill-down: period purchases, variance, recent lines.
final stockItemIntelligenceProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
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
  final range = ref.watch(stockListQueryProvider);
  final result = await ref.read(hexaApiProvider).getStockIntelligence(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
        periodStart: range.periodStart,
        periodEnd: range.periodEnd,
      ).timeout(const Duration(seconds: 15));
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  return result;
});

final stockItemActivityProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, itemId) async {
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
  final result = await ref.read(hexaApiProvider).getStockItemActivity(
        businessId: session.primaryBusiness.id,
        itemId: itemId,
      ).timeout(const Duration(seconds: 15));
  if (providerWasDisposed(disposed)) {
    throw const ProviderFetchAborted();
  }
  return result;
});

/// Optimistic item-detail stock overlays (instant UI after save; cleared on refetch).
final stockItemDetailPatchProvider =
    StateProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, itemId) => const {},
);

void clearStockItemDetailPatch(dynamic ref, {required String itemId}) {
  if (itemId.isEmpty) return;
  ref.read(stockItemDetailPatchProvider(itemId).notifier).state = const {};
}

void applyStockItemDetailPatch(
  dynamic ref, {
  required String itemId,
  required Map<String, dynamic> patch,
}) {
  if (itemId.isEmpty || patch.isEmpty) return;
  ref.read(stockItemDetailPatchProvider(itemId).notifier).update(
        (current) => {...current, ...patch},
      );
  final listPatch = stockListPatchFromStockDetail(patch);
  if (listPatch.isNotEmpty) {
    applyStockListRowPatch(ref, itemId: itemId, patch: listPatch);
  }
}

/// Apply save response instantly; reconcile with server in the background.
void applyStockItemDetailFromSave(
  dynamic ref, {
  required String itemId,
  required Map<String, dynamic> saved,
}) {
  if (itemId.isEmpty || saved.isEmpty) return;
  applyStockItemDetailPatch(ref, itemId: itemId, patch: saved);
  deferInvalidateDelayed(ref, stockItemDetailProvider(itemId));
}

/// Stock row + recent purchases for catalog item detail / sheets.
final stockItemDetailProvider =
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
    try {
      final row = await ref.read(hexaApiProvider).getStockItem(
            businessId: session.primaryBusiness.id,
            itemId: itemId,
          ).timeout(const Duration(seconds: 15));
      if (providerWasDisposed(disposed)) {
        throw const ProviderFetchAborted();
      }
      clearStockItemDetailPatch(ref, itemId: itemId);
      return normalizeStockDetailMap(row);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return {};
      if (providerWasDisposed(disposed)) {
        throw const ProviderFetchAborted();
      }
      rethrow;
    }
  },
);

final stockItemAuditProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, itemId) async {
    final disposed = registerProviderDisposeGuard(ref);
    registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    final rows = await ref.read(hexaApiProvider).listStockAuditForItem(
          businessId: session.primaryBusiness.id,
          itemId: itemId,
        ).timeout(const Duration(seconds: 15));
    if (providerWasDisposed(disposed)) return [];
    return rows;
  },
);

/// Per-item observation physical remaining history.
final stockItemPhysicalCountsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, itemId) async {
    final disposed = registerProviderDisposeGuard(ref);
    registerProviderKeepAliveTimer(ref, const Duration(seconds: 45));
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    final rows = await ref
        .read(hexaApiProvider)
        .listPhysicalCountsForItem(
          businessId: session.primaryBusiness.id,
          itemId: itemId,
          limit: 50,
        )
        .timeout(const Duration(seconds: 15));
    if (providerWasDisposed(disposed)) return [];
    return rows;
  },
);
