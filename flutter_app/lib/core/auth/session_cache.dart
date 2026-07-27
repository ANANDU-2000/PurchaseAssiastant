import 'dart:convert';
import 'dart:developer' as developer;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// Persists last known business list so we can restore the session UI when the API is temporarily unreachable.
class SessionCache {
  SessionCache(this._prefs);

  static const _k = 'session_businesses_cache_json';
  static const _kSuper = 'session_is_super_admin';

  final SharedPreferences _prefs;

  Future<void> saveBusinesses(List<BusinessBrief> list,
      {bool? isSuperAdmin}) async {
    try {
      if (list.isEmpty) return;
      final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
      await _prefs.setString(_k, encoded);
      if (isSuperAdmin != null) {
        await _prefs.setBool(_kSuper, isSuperAdmin);
      }
    } catch (e) {
      developer.log('Failed to save businesses cache: $e',
          name: 'SessionCache');
    }
  }

  bool loadIsSuperAdmin() => _prefs.getBool(_kSuper) ?? false;

  List<BusinessBrief>? loadBusinesses() {
    final s = _prefs.getString(_k);
    if (s == null || s.isEmpty) return null;
    try {
      final list = jsonDecode(s) as List<dynamic>;
      return list
          .map((e) =>
              BusinessBrief.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _prefs.remove(_k);
      await _prefs.remove(_kSuper);
    } catch (e) {
      developer.log('Failed to clear session cache: $e',
          name: 'SessionCache');
    }
  }
}
