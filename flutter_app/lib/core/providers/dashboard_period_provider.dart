import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Preset ranges for dashboard + home insights (must stay in sync).
enum DashboardPeriod { today, week, month, year }

final dashboardPeriodProvider =
    StateProvider<DashboardPeriod>((ref) => DashboardPeriod.month);

(DateTime, DateTime) dashboardDateRange(DashboardPeriod p) {
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  switch (p) {
    case DashboardPeriod.today:
      return (todayStart, now);
    case DashboardPeriod.week:
      final start = todayStart
          .subtract(Duration(days: todayStart.weekday - DateTime.monday));
      return (start, now);
    case DashboardPeriod.month:
      return (DateTime(now.year, now.month, 1), now);
    case DashboardPeriod.year:
      return (DateTime(now.year, 1, 1), now);
  }
}

String dashboardPeriodLabel(DashboardPeriod p) {
  switch (p) {
    case DashboardPeriod.today:
      return 'Today';
    case DashboardPeriod.week:
      return 'Week';
    case DashboardPeriod.month:
      return 'Month';
    case DashboardPeriod.year:
      return 'Year';
  }
}
