import 'dart:convert';

import 'package:hexa_purchase_assistant/core/maintenance/maintenance_payment_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client-only "cloud paid" state per calendar month (device local).
class CloudPaymentLocalRepository {
  CloudPaymentLocalRepository(this._prefs);

  final SharedPreferences _prefs;
  static const _prefsKey = 'pref_cloud_local_paid_v1';

  Map<String, String> _readMap() {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return {};
      return d.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  void _writeMap(Map<String, String> m) {
    _prefs.setString(_prefsKey, jsonEncode(m));
  }

  String _monthKey(DateTime d) => MaintenancePaymentRepository.monthKeyFor(d);

  /// [paidAt] ISO-8601 for [month] key.
  void markCurrentMonthPaid(DateTime now) {
    final k = _monthKey(now);
    final m = _readMap();
    m[k] = now.toIso8601String();
    _writeMap(m);
  }

  DateTime? paidAtForMonth(DateTime d) {
    final k = _monthKey(d);
    final iso = _readMap()[k];
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }
}
