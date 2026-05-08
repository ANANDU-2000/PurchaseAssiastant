import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/trade_purchase_models.dart';

/// Cached GET trade purchase (keepAlive). Always invalidate after edit, payment,
/// or delete so a revisit does not show stale rows.
final tradePurchaseDetailProvider =
    FutureProvider.autoDispose.family<TradePurchase, String>((ref, purchaseId) async {
  ref.keepAlive();
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('no session');
  final m = await ref.read(hexaApiProvider).getTradePurchase(
        businessId: session.primaryBusiness.id,
        purchaseId: purchaseId,
      );
  return TradePurchase.fromJson(m);
});
