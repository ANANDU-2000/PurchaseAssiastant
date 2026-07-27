import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';

final businessUserProfileProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    return ref.read(hexaApiProvider).getBusinessUser(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userActivityFeedProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserActivity(
          businessId: session.primaryBusiness.id,
          userId: userId,
          days: 30,
        );
  },
);

final userStockHistoryProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserStockAdjustments(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userPurchasesProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserPurchases(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userPermissionsProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    return ref.read(hexaApiProvider).getUserPermissions(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userCreatedItemsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return [];
    return ref.read(hexaApiProvider).listUserCreatedItems(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);

final userLedgerGroupedProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, userId) async {
    final session = ref.watch(sessionProvider);
    if (session == null) return {};
    return ref.read(hexaApiProvider).listUserLedgerGrouped(
          businessId: session.primaryBusiness.id,
          userId: userId,
        );
  },
);
