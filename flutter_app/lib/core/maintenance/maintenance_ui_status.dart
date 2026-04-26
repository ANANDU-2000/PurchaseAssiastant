import 'package:hexa_purchase_assistant/core/maintenance/maintenance_month_record.dart';
import 'package:hexa_purchase_assistant/core/maintenance/maintenance_payment_repository.dart';

/// Home card + alerts: single source for copy and colors.
enum MaintenanceUiStatus {
  paid,
  /// Before last day, or before 9:00 on last day (grey / subtle).
  upcoming,
  /// Last calendar day, unpaid, before 09:00.
  dueToday,
  /// Unpaid, same month, on/after due instant (last day 09:00+).
  overdue,
}

MaintenanceUiStatus maintenanceUiStatus({
  required DateTime now,
  required MaintenanceMonthRecord record,
}) {
  if (record.isPaid) return MaintenanceUiStatus.paid;
  final y = now.year;
  final m = now.month;
  final lastD = MaintenancePaymentRepository.lastDayOfMonth(y, m);
  final due = DateTime(y, m, lastD, 9, 0);
  if (now.day < lastD) return MaintenanceUiStatus.upcoming;
  if (now.day == lastD) {
    if (now.isBefore(due)) return MaintenanceUiStatus.dueToday;
    return MaintenanceUiStatus.overdue;
  }
  // Calendar day after last day cannot happen in same month.
  return MaintenanceUiStatus.upcoming;
}
