import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _kSuppliers = 'recent_supplier_picks_v1';
const _kBrokers = 'recent_broker_picks_v1';
const _kMax = 5;

Future<List<String>> loadRecentSupplierIds() async {
  return _loadIds(_kSuppliers);
}

Future<void> recordRecentSupplierId(String id) async {
  if (id.isEmpty) return;
  await _saveIds(_kSuppliers, await _bump(_kSuppliers, id));
}

Future<List<String>> loadRecentBrokerIds() async {
  return _loadIds(_kBrokers);
}

Future<void> recordRecentBrokerId(String id) async {
  if (id.isEmpty) return;
  await _saveIds(_kBrokers, await _bump(_kBrokers, id));
}

Future<List<String>> _loadIds(String key) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(key);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  } catch (_) {
    return [];
  }
}

Future<List<String>> _bump(String key, String id) async {
  final cur = await _loadIds(key);
  cur.removeWhere((e) => e == id);
  cur.insert(0, id);
  if (cur.length > _kMax) return cur.sublist(0, _kMax);
  return cur;
}

Future<void> _saveIds(String key, List<String> ids) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(key, jsonEncode(ids));
}
