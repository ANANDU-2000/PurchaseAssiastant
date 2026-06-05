import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/trade_purchase_models.dart';

/// Purchase soft-deleted or missing — detail UI should pop and bust caches.
class TradePurchaseUnavailableError implements Exception {
  const TradePurchaseUnavailableError([
    this.message = 'This purchase was deleted.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// While [markPurchaseDelivered] round-trips, holds target [TradePurchase.isDelivered].
final tradePurchaseDeliveryOptimisticProvider =
    StateProvider.autoDispose.family<bool?, String>((ref, _) => null);

/// Hard cap so detail never sits on [DetailSkeleton] indefinitely on slow networks.
const Duration kTradePurchaseDetailFetchTimeout = Duration(seconds: 15);

/// Cached GET trade purchase (keepAlive). Always invalidate after edit, payment,
/// or delete so a revisit does not show stale rows.
final tradePurchaseDetailProvider =
    FutureProvider.autoDispose.family<TradePurchase, String>((ref, purchaseId) async {
  ref.keepAlive();
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('no session');
  try {
    final m = await ref
        .read(hexaApiProvider)
        .getTradePurchase(
          businessId: session.primaryBusiness.id,
          purchaseId: purchaseId,
        )
        .timeout(kTradePurchaseDetailFetchTimeout);
    final purchase = TradePurchase.fromJson(m);
    if (purchase.statusEnum == PurchaseStatus.deleted) {
      throw const TradePurchaseUnavailableError();
    }
    return purchase;
  } on TradePurchaseUnavailableError {
    rethrow;
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      throw const TradePurchaseUnavailableError();
    }
    rethrow;
  } on TimeoutException {
    throw Exception(
      'Could not load purchase in time — check your connection and try again.',
    );
  }
});
