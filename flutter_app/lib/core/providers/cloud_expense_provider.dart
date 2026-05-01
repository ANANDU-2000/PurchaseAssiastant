import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';
import '../services/offline_store.dart';

/// Server-ensured row + computed flags (`show_alert`, `paid_up`, `history`, …).
final cloudCostProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  final bid = session.primaryBusiness.id;
  try {
    final m = await ref.read(hexaApiProvider).getCloudCost(
          businessId: bid,
        );
    await OfflineStore.cacheCloudCost(bid, Map<String, dynamic>.from(m));
    return Map<String, dynamic>.from(m);
  } on DioException {
    return OfflineStore.getCachedCloudCost(bid) ?? <String, dynamic>{};
  } catch (_) {
    return OfflineStore.getCachedCloudCost(bid) ?? <String, dynamic>{};
  }
});
