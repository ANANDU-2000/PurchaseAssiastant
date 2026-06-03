import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;

final purchaseDamageReportsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, purchaseId) async {
  final session = ref.watch(activeSessionProvider);
  if (session == null || purchaseId.isEmpty) return [];
  return ref.read(hexaApiProvider).listPurchaseDamageReports(
        businessId: session.primaryBusiness.id,
        purchaseId: purchaseId,
      );
});

/// Owner home: pending damage reports awaiting approval.
final pendingDamageReportsCountProvider = FutureProvider<int>((ref) async {
  final session = ref.watch(activeSessionProvider);
  if (session == null) return 0;
  final role = session.primaryBusiness.role.toLowerCase();
  if (role != 'owner' && role != 'manager' && !session.isSuperAdmin) {
    return 0;
  }
  return ref.read(hexaApiProvider).getPendingDamageReportsCount(
        businessId: session.primaryBusiness.id,
      );
});
