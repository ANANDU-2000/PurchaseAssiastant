import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../auth/session_notifier.dart' show activeSessionProvider, hexaApiProvider;
import '../../features/shell/shell_branch_provider.dart';
import 'analytics_kpi_provider.dart';

const Duration _reportsTimeout = Duration(seconds: 15);

final reportsPeriodComparisonProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final link = ref.keepAlive();
  final t = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(t.cancel);
  if (!shellBranchIsVisible(ref, ShellBranch.reports)) return <String, dynamic>{};
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return <String, dynamic>{};
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).tradeReportPeriodComparison(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      ).timeout(_reportsTimeout);
});

final reportsMovementSummaryProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final link = ref.keepAlive();
  final t = Timer(const Duration(minutes: 3), link.close);
  ref.onDispose(t.cancel);
  if (!shellBranchIsVisible(ref, ShellBranch.reports)) return <String, dynamic>{};
  final session = ref.watch(activeSessionProvider);
  final range = ref.watch(analyticsDateRangeProvider);
  if (session == null) return <String, dynamic>{};
  final fmt = DateFormat('yyyy-MM-dd');
  return ref.read(hexaApiProvider).tradeReportMovementSummary(
        businessId: session.primaryBusiness.id,
        from: fmt.format(range.from),
        to: fmt.format(range.to),
      ).timeout(_reportsTimeout);
});
