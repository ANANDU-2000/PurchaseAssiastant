import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../auth/session_notifier.dart'
    show activeSessionProvider, hexaApiProvider, sessionProvider;
import '../../features/shell/shell_branch_provider.dart';
import 'home_dashboard_provider.dart' show homeChecklistFetchEnabledProvider;

bool _isAuthFailure(Object e) {
  if (e is DioException) {
    final sc = e.response?.statusCode;
    return sc == 401 || sc == 403;
  }
  return false;
}

bool _checklistSessionActive(Ref ref) {
  if (providerSkipApi(ref)) return false;
  return ref.watch(activeSessionProvider) != null;
}

final checklistTodayProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final disposed = registerProviderDisposeGuard(ref);
  if (!_checklistSessionActive(ref)) return <String, dynamic>{};
  if (shellBranchIsVisible(ref, ShellBranch.home) &&
      !ref.watch(homeChecklistFetchEnabledProvider)) {
    return <String, dynamic>{};
  }
  final session = ref.read(sessionProvider);
  if (session == null) return <String, dynamic>{};
  try {
    final result = await ref.read(hexaApiProvider).getChecklistToday(
          businessId: session.primaryBusiness.id,
        );
    if (providerWasDisposed(disposed)) return <String, dynamic>{};
    return result;
  } catch (e) {
    if (_isAuthFailure(e)) rethrow;
    rethrow;
  }
});

final checklistTemplatesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  if (!_checklistSessionActive(ref)) return <Map<String, dynamic>>[];
  final session = ref.read(sessionProvider);
  if (session == null) return [];
  return ref.read(hexaApiProvider).getChecklistTemplates(
        businessId: session.primaryBusiness.id,
      );
});

final usageTodayProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (!_checklistSessionActive(ref)) return <String, dynamic>{};
  final session = ref.read(sessionProvider);
  if (session == null) return <String, dynamic>{};
  return ref.read(hexaApiProvider).getUsageToday(
        businessId: session.primaryBusiness.id,
      );
});

final itemTodaySnapshotProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>((ref, itemId) async {
  if (!_checklistSessionActive(ref) || itemId.isEmpty) return null;
  final session = ref.read(sessionProvider);
  if (session == null) return null;
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final rows = await ref.read(hexaApiProvider).listDailySnapshots(
        businessId: session.primaryBusiness.id,
        fromDate: today,
        toDate: today,
        itemId: itemId,
      );
  if (rows.isEmpty) return null;
  return rows.first;
});

final operationalReportsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final link = ref.keepAlive();
  final t = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(t.cancel);
  if (!_checklistSessionActive(ref)) return <String, dynamic>{};
  // IndexedStack mounts Reports off-screen — only fetch when Reports is visible.
  if (!shellBranchIsVisible(ref, ShellBranch.reports)) return <String, dynamic>{};
  final session = ref.read(sessionProvider);
  if (session == null) return <String, dynamic>{};
  return ref
      .read(hexaApiProvider)
      .getOperationalReports(
        businessId: session.primaryBusiness.id,
      )
      .timeout(
        const Duration(seconds: 12),
        onTimeout: () => <String, dynamic>{},
      );
});
