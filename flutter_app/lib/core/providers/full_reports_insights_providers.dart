import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/provider_api_guard.dart';
import '../../features/shell/shell_branch_provider.dart';

/// Insights copy block for the full Reports screen (legacy analytics API removed).
final fullReportsInsightsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  if (providerSkipApi(ref)) return <String, dynamic>{};
  if (!shellBranchIsVisible(ref, ShellBranch.reports)) return <String, dynamic>{};
  return <String, dynamic>{};
});

/// Monthly goals strip on Reports (legacy analytics API removed).
final fullReportsGoalsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  if (providerSkipApi(ref)) return null;
  if (!shellBranchIsVisible(ref, ShellBranch.reports)) return null;
  return null;
});
