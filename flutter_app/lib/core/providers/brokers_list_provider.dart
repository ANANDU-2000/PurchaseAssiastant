import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

final brokersListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  final api = ref.read(hexaApiProvider);
  return api.listBrokers(businessId: session.primaryBusiness.id);
});
