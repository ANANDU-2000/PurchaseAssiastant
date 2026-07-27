import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_error_messages.dart' show shouldQueueScanOffline;
import '../auth/session_notifier.dart';
import '../services/offline_store.dart';
import 'delivery_write_resilience.dart';

/// Mark purchase arrived — queue when warehouse has no connectivity.
Future<({bool queued, Map<String, dynamic>? body})> markPurchaseArrivedResilient({
  required WidgetRef ref,
  required String businessId,
  required String purchaseId,
  String? notes,
  String? truckNumber,
  String? driverContact,
  double? damageQty,
  double? missingQty,
  bool? brokerConfirmed,
}) async {
  try {
    final body = await resilientPurchaseWrite<Map<String, dynamic>>(
      write: () => ref.read(hexaApiProvider).arrivePurchase(
            businessId: businessId,
            purchaseId: purchaseId,
            notes: notes,
            truckNumber: truckNumber,
            driverContact: driverContact,
            damageQty: damageQty,
            missingQty: missingQty,
            brokerConfirmed: brokerConfirmed,
          ),
      ref: ref,
      businessId: businessId,
      purchaseId: purchaseId,
      reconcileSuccess: purchasePassedArriveGate,
      mapReconciled: (p) => p,
    );
    return (queued: false, body: Map<String, dynamic>.from(body));
  } on DioException catch (e) {
    if (!shouldQueueScanOffline(e)) rethrow;
    await OfflineStore.queuePurchaseArrive(
      businessId: businessId,
      purchaseId: purchaseId,
      notes: notes,
    );
    return (queued: true, body: null);
  }
}

/// Verify all lines at ordered qty — no second sheet when counts match PO.
Future<Map<String, dynamic>> verifyPurchaseDeliveryAsOrdered({
  required WidgetRef ref,
  required String businessId,
  required String purchaseId,
  required List<({String lineId, double orderedQty})> lines,
  String? notes,
}) async {
  final payload = [
    for (final l in lines)
      if (l.lineId.isNotEmpty)
        {
          'line_id': l.lineId,
          'received_qty': l.orderedQty,
          'damaged_qty': 0,
          'return_qty': 0,
        },
  ];
  final body = await resilientPurchaseWrite<Map<String, dynamic>>(
    write: () => ref.read(hexaApiProvider).verifyPurchaseDelivery(
          businessId: businessId,
          purchaseId: purchaseId,
          lines: payload,
          notes: notes,
        ),
    ref: ref,
    businessId: businessId,
    purchaseId: purchaseId,
    reconcileSuccess: purchasePassedVerifyGate,
    mapReconciled: (p) => p,
  );
  return Map<String, dynamic>.from(body);
}
