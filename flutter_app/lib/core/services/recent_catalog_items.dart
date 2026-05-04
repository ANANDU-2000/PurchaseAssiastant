import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../json_coerce.dart';

const _kKey = 'recent_catalog_item_picks_v1';
const _kMax = 5;

/// A single recently-picked catalog item stored in SharedPreferences.
class RecentCatalogItem {
  const RecentCatalogItem({
    required this.id,
    required this.name,
    this.lastPrice,
    this.unit,
    this.categoryName,
    this.kgPerBag,
  });

  final String id;
  final String name;
  final double? lastPrice;
  final String? unit;
  final String? categoryName;
  final double? kgPerBag;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (lastPrice != null) 'last_price': lastPrice,
        if (unit != null) 'unit': unit,
        if (categoryName != null) 'category_name': categoryName,
        if (kgPerBag != null) 'kg_per_bag': kgPerBag,
      };

  factory RecentCatalogItem.fromJson(Map<String, dynamic> j) =>
      RecentCatalogItem(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        lastPrice: coerceToDoubleNullable(j['last_price']),
        unit: j['unit']?.toString(),
        categoryName: j['category_name']?.toString(),
        kgPerBag: coerceToDoubleNullable(j['kg_per_bag']),
      );

  /// Convert to the same map shape used by the wizard catalog search hits.
  Map<String, dynamic> toSearchHit() => {
        'id': id,
        'name': name,
        if (lastPrice != null) 'last_price': lastPrice,
        'default_unit': unit ?? 'kg',
        'default_purchase_unit': unit ?? 'kg',
        if (categoryName != null) 'category_name': categoryName,
        if (kgPerBag != null) 'default_kg_per_bag': kgPerBag,
        '_recent': true,
        '_score': 200,
      };
}

/// Reads the saved LRU list (most-recent first).
Future<List<RecentCatalogItem>> loadRecentCatalogItems() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kKey);
  if (raw == null || raw.isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .whereType<Map<String, dynamic>>()
        .map(RecentCatalogItem.fromJson)
        .where((r) => r.id.isNotEmpty && r.name.isNotEmpty)
        .toList();
  } catch (_) {
    return [];
  }
}

/// Records a picked item. Moves to front, caps at [_kMax], persists.
Future<void> recordRecentCatalogItem(RecentCatalogItem item) async {
  final prefs = await SharedPreferences.getInstance();
  var list = await loadRecentCatalogItems();
  list.removeWhere((r) => r.id == item.id);
  list.insert(0, item);
  if (list.length > _kMax) list = list.sublist(0, _kMax);
  await prefs.setString(
    _kKey,
    jsonEncode(list.map((r) => r.toJson()).toList()),
  );
}
