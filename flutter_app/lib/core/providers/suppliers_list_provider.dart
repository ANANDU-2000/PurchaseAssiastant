import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

/// Kept alive so supplier pickers never cold-load across navigations.
final suppliersListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  return api.listSuppliers(businessId: session.primaryBusiness.id);
});
