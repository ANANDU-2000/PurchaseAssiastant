import 'dart:convert';

import 'package:hexa_purchase_assistant/core/maintenance/maintenance_month_record.dart';
import 'package:hexa_purchase_assistant/core/maintenance/maintenance_payment_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local JSON storage for maintenance months (append-only history, capped).
class MaintenancePaymentRepository {
  MaintenancePaymentRepository(this._prefs);

  final SharedPreferences _prefs;
  static const int _maxHistoryMonths = 36;

  List<MaintenanceMonthRecord> _decode() {
    final raw = _prefs.getString(MaintenancePaymentConstants.recordsPrefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return [];
      final out = <MaintenanceMonthRecord>[];
      for (final e in list) {
        if (e is Map<String, dynamic>) {
          final r = MaintenanceMonthRecord.fromJson(e);
          if (r != null) out.add(r);
        } else if (e is Map) {
          final r = MaintenanceMonthRecord.fromJson(Map<String, dynamic>.from(e));
          if (r != null) out.add(r);
        }
      }
      out.sort((a, b) => b.month.compareTo(a.month));
      return out;
    } catch (_) {
      return [];
    }
  }

  void _encode(List<MaintenanceMonthRecord> rows) {
    var list = List<MaintenanceMonthRecord>.from(rows);
    list.sort((a, b) => b.month.compareTo(a.month));
    if (list.length > _maxHistoryMonths) {
      list = list.sublist(0, _maxHistoryMonths);
    }
    final str = jsonEncode(list.map((e) => e.toJson()).toList());
    _prefs.setString(MaintenancePaymentConstants.recordsPrefsKey, str);
  }

  static String monthKeyFor(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}';
  }

  /// Last calendar day of [year]-[month] in local time.
  static int lastDayOfMonth(int year, int month) {
    return DateTime(year, month + 1, 0).day;
  }

  /// [DateTime] at 09:00 on the last day of the month containing [d] (local).
  static DateTime dueInstantForMonth(DateTime d) {
    final y = d.year;
    final m = d.month;
    final last = lastDayOfMonth(y, m);
    return DateTime(y, m, last, 9, 0);
  }

  /// Ensures a record exists for the current `YYYY-MM` (unpaid if new). Call on app open.
  List<MaintenanceMonthRecord> ensureOnAppOpen(DateTime now) {
    final list = _decode();
    final key = monthKeyFor(now);
    final idx = list.indexWhere((e) => e.month == key);
    if (idx < 0) {
      list.add(
        MaintenanceMonthRecord(
          month: key,
          amount: MaintenancePaymentConstants.amountInr,
          status: 'unpaid',
          paidAt: null,
        ),
      );
      _encode(list);
      return _decode();
    }
    return list;
  }

  MaintenanceMonthRecord? currentFor(DateTime now) {
    final key = monthKeyFor(now);
    final list = _decode();
    for (final r in list) {
      if (r.month == key) return r;
    }
    return null;
  }

  List<MaintenanceMonthRecord> allRowsNewestFirst() => _decode();

  bool get remindersEnabled =>
      _prefs.getBool(MaintenancePaymentConstants.remindersEnabledPrefsKey) ??
      true;

  Future<void> setRemindersEnabled(bool v) async {
    await _prefs.setBool(
        MaintenancePaymentConstants.remindersEnabledPrefsKey, v);
  }

  /// No-op if current month is already paid.
  Future<MaintenanceMonthRecord?> markCurrentMonthPaid(DateTime now) async {
    final list = _decode();
    final key = monthKeyFor(now);
    final idx = list.indexWhere((e) => e.month == key);
    if (idx < 0) {
      list.add(
        MaintenanceMonthRecord(
          month: key,
          amount: MaintenancePaymentConstants.amountInr,
          status: 'paid',
          paidAt: now,
        ),
      );
    } else {
      final r = list[idx];
      if (r.isPaid) return r;
      list[idx] = r.copyWith(
        status: 'paid',
        paidAt: now,
        amount: MaintenancePaymentConstants.amountInr,
      );
    }
    _encode(list);
    return list.firstWhere((e) => e.month == key);
  }
}
