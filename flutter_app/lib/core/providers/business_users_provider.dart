import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_notifier.dart';

final businessUsersListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).listBusinessUsers(
        businessId: session.primaryBusiness.id,
        includeInactive: true,
      );
});

void invalidateUserManagementCaches(dynamic ref) {
  ref.invalidate(businessUsersListProvider);
}
