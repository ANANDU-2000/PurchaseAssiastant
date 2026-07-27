import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Cached JSON rules from [assets/config/unit_rules_master.json].
class UnitRulesLoader {
  UnitRulesLoader._();

  static Map<String, dynamic>? _cache;

  static Future<Map<String, dynamic>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/config/unit_rules_master.json');
    _cache = json.decode(raw) as Map<String, dynamic>;
    return _cache!;
  }

  /// For tests — inject parsed rules without asset bundle.
  static void debugSetRules(Map<String, dynamic> rules) {
    _cache = rules;
  }

  static void clearCache() {
    _cache = null;
  }
}
