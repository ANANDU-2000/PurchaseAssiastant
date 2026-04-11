import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/session.dart';

/// Persists last known business list so we can restore the session UI when the API is temporarily unreachable.
class SessionCache {
  SessionCache(this._prefs);

  static const _k = 'session_businesses_cache_json';

  final SharedPreferences _prefs;

  Future<void> saveBusinesses(List<BusinessBrief> list) async {
    if (list.isEmpty) return;
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await _prefs.setString(_k, encoded);
  }

  List<BusinessBrief>? loadBusinesses() {
    final s = _prefs.getString(_k);
    if (s == null || s.isEmpty) return null;
    try {
      final list = jsonDecode(s) as List<dynamic>;
      return list
          .map((e) => BusinessBrief.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    await _prefs.remove(_k);
  }
}
