import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

final entryDetailProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, entryId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) {
    throw StateError('Not signed in');
  }
  final api = ref.read(hexaApiProvider);
  return api.getEntry(businessId: session.primaryBusiness.id, entryId: entryId);
});
