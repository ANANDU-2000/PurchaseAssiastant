import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/shell/shell_branch_provider.dart';
import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import 'home_dashboard_provider.dart'
    show homeOverviewReadyForSatellites, homePendingDamageFetchEnabledProvider;

final purchaseDamageReportsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, purchaseId) async {
  final session = ref.watch(activeSessionProvider);
  if (session == null || purchaseId.isEmpty) return [];
  try {
    return await ref.read(hexaApiProvider).listPurchaseDamageReports(
          businessId: session.primaryBusiness.id,
          purchaseId: purchaseId,
        );
  } catch (_) {
    // Pre-057 schema or transient API errors — avoid console retry storms on detail.
    return [];
  }
});

/// Owner home: pending damage reports awaiting approval.
final pendingDamageReportsCountProvider = FutureProvider<int>((ref) async {
  if (shellBranchIsVisible(ref, ShellBranch.home) &&
      !ref.watch(homePendingDamageFetchEnabledProvider)) {
    return 0;
  }
  if (!homeOverviewReadyForSatellites(ref)) return 0;
  final session = ref.watch(activeSessionProvider);
  if (session == null) return 0;
  final role = session.primaryBusiness.role.toLowerCase();
  if (role != 'owner' && role != 'manager' && !session.isSuperAdmin) {
    return 0;
  }
  try {
    return await ref.read(hexaApiProvider).getPendingDamageReportsCount(
          businessId: session.primaryBusiness.id,
        );
  } catch (_) {
    return 0;
  }
});
