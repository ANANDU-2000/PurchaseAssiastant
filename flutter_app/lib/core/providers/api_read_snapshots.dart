import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/hexa_api.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import '../auth/provider_api_guard.dart';

final Map<String, Future<List<Map<String, dynamic>>>> _tradePurchasesRecentInflight =
    {};

/// SSOT for `GET …/stock/audit/recent` — one fetch serves home, stock tabs, and activity.
final stockAuditRecentSnapshotProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  if (providerSkipApi(ref)) return [];
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  final rows = await ref.read(hexaApiProvider).listStockAuditRecent(
        businessId: session.primaryBusiness.id,
        limit: HexaApi.stockAuditRecentMaxLimit,
      );
  if (providerWasDisposed(disposed)) return [];
  return rows;
});

/// SSOT for recent unfiltered `GET …/trade-purchases?limit=50` (alerts + catalog intel).
final tradePurchasesRecentSnapshotProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  registerProviderKeepAliveTimer(ref, const Duration(minutes: 2));
  if (providerSkipApi(ref)) return [];
  final session = ref.watch(activeSessionProvider);
  if (session == null) return [];
  final bid = session.primaryBusiness.id;
  final page = await _tradePurchasesRecentInflight.putIfAbsent(
    bid,
    () => ref
        .read(hexaApiProvider)
        .listTradePurchases(businessId: bid, limit: 50)
        .whenComplete(() => _tradePurchasesRecentInflight.remove(bid)),
  );
  if (providerWasDisposed(disposed)) return [];
  return page;
});

void bustStockAuditRecentSnapshot(dynamic ref) {
  ref.invalidate(stockAuditRecentSnapshotProvider);
}

void bustTradePurchasesRecentSnapshot(dynamic ref) {
  ref.invalidate(tradePurchasesRecentSnapshotProvider);
}
