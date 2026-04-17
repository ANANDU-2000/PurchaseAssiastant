import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

final tradePurchasesListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listTradePurchases(
        businessId: session.primaryBusiness.id,
      );
});
