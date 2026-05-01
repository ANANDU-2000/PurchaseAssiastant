import 'package:hive_flutter/hive_flutter.dart';

/// Local persistence for offline-first UX (dashboard cache, future entry queue).
class OfflineStore {
  OfflineStore._();

  static const _boxCache = 'offline_cache';
  static const _boxEntries = 'offline_entries';
  static const _boxPurchaseWizardDraft = 'purchase_wizard_draft';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_boxCache);
    await Hive.openBox(_boxEntries);
    await Hive.openBox(_boxPurchaseWizardDraft);
  }

  static Box get _purchaseWizardDraft => Hive.box(_boxPurchaseWizardDraft);

  /// JSON blob for incomplete purchase wizard (same shape as prefs draft).
  static Future<void> putPurchaseWizardDraft(String businessId, String json) async {
    await _purchaseWizardDraft.put(businessId, json);
  }

  static String? getPurchaseWizardDraft(String businessId) {
    final v = _purchaseWizardDraft.get(businessId);
    if (v is String && v.isNotEmpty) return v;
    return null;
  }

  static Future<void> clearPurchaseWizardDraft(String businessId) async {
    await _purchaseWizardDraft.delete(businessId);
  }

  static Box get _cache => Hive.box(_boxCache);
  static Box get _entries => Hive.box(_boxEntries);

  static Future<void> cacheDashboardMap(Map<String, dynamic> summary) async {
    await _cache.put('dashboard', {
      ...summary,
      'cachedAt': DateTime.now().toIso8601String(),
    });
  }

  /// Returns cached analytics summary map (no `cachedAt` strip) or null if stale/missing.
  static Map<String, dynamic>? getCachedDashboardSummary() {
    final raw = _cache.get('dashboard');
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final at = m['cachedAt'] as String?;
    if (at == null) return null;
    final cachedAt = DateTime.tryParse(at);
    if (cachedAt == null) return null;
    if (DateTime.now().difference(cachedAt) > const Duration(hours: 2)) {
      return null;
    }
    return m;
  }

  static Future<void> queueEntry(Map<String, dynamic> entryData) async {
    final id = 'offline_${DateTime.now().millisecondsSinceEpoch}';
    await _entries.put(id, {
      'id': id,
      'data': entryData,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static List<Map<String, dynamic>> getPendingEntries() {
    final out = <Map<String, dynamic>>[];
    for (final k in _entries.keys) {
      final v = _entries.get(k);
      if (v is Map && v['status'] == 'pending') {
        out.add(Map<String, dynamic>.from(v));
      }
    }
    return out;
  }

  static Future<void> markSynced(String id) async {
    await _entries.delete(id);
  }

  static Future<void> cacheSuppliers(List<dynamic> list) async {
    await _cache.put('suppliers', list);
  }

  static List<dynamic>? getCachedSuppliers() =>
      _cache.get('suppliers') as List<dynamic>?;

  static Future<void> cacheCatalogItems(List<dynamic> list) async {
    await _cache.put('catalog_items', list);
  }

  static List<dynamic>? getCachedCatalogItems() =>
      _cache.get('catalog_items') as List<dynamic>?;
}
