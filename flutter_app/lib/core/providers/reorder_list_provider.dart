import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

final reorderListProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, status) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listReorderEntries(
        businessId: session.primaryBusiness.id,
        status: status,
      );
});

final reorderPendingCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final rows = await ref.watch(reorderListProvider('pending').future);
  return rows.length;
});
