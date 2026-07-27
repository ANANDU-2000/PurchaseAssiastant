import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_error_messages.dart';
import '../auth/session_notifier.dart';
import '../models/trade_purchase_models.dart';

/// Purchase has left the in-transit bucket (arrive POST may have succeeded).
bool purchasePassedArriveGate(Map<String, dynamic> json) {
  final ds = parseDeliveryStatus(json['delivery_status']?.toString());
  return ds != DeliveryStatus.pending &&
      ds != DeliveryStatus.dispatched &&
      ds != DeliveryStatus.inTransit &&
      ds != DeliveryStatus.cancelled;
}

/// Staff verify POST may have succeeded even when the client timed out.
bool purchasePassedVerifyGate(Map<String, dynamic> json) {
  final ds = parseDeliveryStatus(json['delivery_status']?.toString());
  return ds.readyForOwnerCommit || ds == DeliveryStatus.stockCommitted;
}

Future<Map<String, dynamic>?> fetchPurchaseIfWriteMaybeSucceeded({
  required WidgetRef ref,
  required String businessId,
  required String purchaseId,
  required bool Function(Map<String, dynamic> purchase) success,
}) async {
  try {
    final body = await ref.read(hexaApiProvider).getTradePurchase(
          businessId: businessId,
          purchaseId: purchaseId,
        );
    if (success(body)) return body;
  } catch (e, st) {
    debugPrint('fetchPurchaseIfWriteMaybeSucceeded: $e\n$st');
  }
  return null;
}

bool _isAmbiguousWriteFailure(Object error) {
  if (error is! DioException) return false;
  if (dioIsNetworkError(error)) return true;
  return error.type == DioExceptionType.receiveTimeout ||
      error.type == DioExceptionType.sendTimeout;
}

/// Run a purchase mutation; on slow Render / timeout, reconcile via GET detail.
Future<T> resilientPurchaseWrite<T>({
  required Future<T> Function() write,
  required WidgetRef ref,
  required String businessId,
  required String purchaseId,
  required bool Function(Map<String, dynamic> purchase) reconcileSuccess,
  required T Function(Map<String, dynamic> purchase) mapReconciled,
}) async {
  try {
    return await write();
  } catch (e) {
    if (!_isAmbiguousWriteFailure(e)) rethrow;
    final body = await fetchPurchaseIfWriteMaybeSucceeded(
      ref: ref,
      businessId: businessId,
      purchaseId: purchaseId,
      success: reconcileSuccess,
    );
    if (body != null) return mapReconciled(body);
    rethrow;
  }
}
