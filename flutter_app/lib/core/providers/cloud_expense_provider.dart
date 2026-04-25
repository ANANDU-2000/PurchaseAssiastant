import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

/// Server-ensured row + computed flags (`show_alert`, `paid_up`, `history`, …).
final cloudCostProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return {};
  return ref.read(hexaApiProvider).getCloudCost(
        businessId: session.primaryBusiness.id,
      );
});
