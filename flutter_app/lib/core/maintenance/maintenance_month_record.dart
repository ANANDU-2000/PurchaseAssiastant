import 'package:hexa_purchase_assistant/core/maintenance/maintenance_payment_constants.dart';

/// One calendar month of maintenance payment state (local device only).
class MaintenanceMonthRecord {
  const MaintenanceMonthRecord({
    required this.month,
    required this.amount,
    required this.status,
    this.paidAt,
  });

  /// `YYYY-MM`
  final String month;
  final int amount;
  /// `paid` | `unpaid`
  final String status;
  final DateTime? paidAt;

  bool get isPaid => status == 'paid';

  MaintenanceMonthRecord copyWith({
    String? month,
    int? amount,
    String? status,
    DateTime? paidAt,
  }) {
    return MaintenanceMonthRecord(
      month: month ?? this.month,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      paidAt: paidAt ?? this.paidAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'month': month,
        'amount': amount,
        'status': status,
        'paid_at': paidAt?.toIso8601String(),
      };

  static MaintenanceMonthRecord? fromJson(Map<String, dynamic> m) {
    final mon = m['month']?.toString();
    if (mon == null || mon.isEmpty) return null;
    final amt = (m['amount'] as num?)?.toInt() ??
        MaintenancePaymentConstants.amountInr;
    final st = m['status']?.toString() ?? 'unpaid';
    final pa = m['paid_at'];
    DateTime? pat;
    if (pa is String && pa.isNotEmpty) {
      pat = DateTime.tryParse(pa);
    }
    return MaintenanceMonthRecord(
      month: mon,
      amount: amt,
      status: st == 'paid' ? 'paid' : 'unpaid',
      paidAt: pat,
    );
  }
}
