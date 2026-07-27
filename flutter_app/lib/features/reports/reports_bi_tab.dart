/// Reports shell tabs (query param: `tab`).
enum ReportsBiTab {
  overview,
  items,
  purchases,
  stock,
}

extension ReportsBiTabX on ReportsBiTab {
  String get queryValue => switch (this) {
        ReportsBiTab.overview => 'overview',
        ReportsBiTab.items => 'items',
        ReportsBiTab.purchases => 'purchase',
        ReportsBiTab.stock => 'stock',
      };

  String get shortLabel => switch (this) {
        ReportsBiTab.overview => 'Overview',
        ReportsBiTab.items => 'Items',
        ReportsBiTab.purchases => 'Purchases',
        ReportsBiTab.stock => 'Stock',
      };

  static const primaryTabs = [
    ReportsBiTab.overview,
    ReportsBiTab.items,
    ReportsBiTab.purchases,
    ReportsBiTab.stock,
  ];

  /// Maps legacy query values to a primary tab.
  static ReportsBiTab resolveFromQuery(String? raw) {
    return fromQuery(raw) ?? ReportsBiTab.overview;
  }

  static ReportsBiTab? fromQuery(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final k = raw.trim().toLowerCase();
    return switch (k) {
      'overview' || 'ring' => ReportsBiTab.overview,
      'items' ||
      'item' ||
      'categories' ||
      'category' ||
      'subcategories' ||
      'subcategory' ||
      'types' ||
      'usage' =>
        ReportsBiTab.items,
      'purchase' ||
      'purchases' ||
      'suppliers' ||
      'supplier' ||
      'supp' ||
      'brokers' ||
      'broker' =>
        ReportsBiTab.purchases,
      'stock' ||
      'stock_intel' ||
      'slow' ||
      'slow_moving' ||
      'slowmoving' ||
      'dead' ||
      'dead_stock' ||
      'deadstock' ||
      'movement' ||
      'stock_movement' ||
      'activity' =>
        ReportsBiTab.stock,
      _ => null,
    };
  }

  /// Optional stock section from `?section=` when tab is stock.
  static String? stockSectionFromQuery(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final k = raw.trim().toLowerCase();
    return switch (k) {
      'slow' || 'slow_moving' => 'slow',
      'dead' || 'dead_stock' => 'dead',
      'fast' || 'fast_moving' => 'fast',
      'low' => 'low',
      'out' => 'out',
      'current' => 'current',
      _ => null,
    };
  }

  /// Legacy tab query that implied a filter preset (applied on navigation).
  static ReportsLegacyFilterPreset? legacyFilterPreset(String? tabRaw) {
    if (tabRaw == null) return null;
    final k = tabRaw.trim().toLowerCase();
    return switch (k) {
      'categories' || 'category' => ReportsLegacyFilterPreset.categoryFocus,
      'subcategories' || 'subcategory' || 'types' =>
        ReportsLegacyFilterPreset.subcategoryFocus,
      'suppliers' || 'supplier' => ReportsLegacyFilterPreset.supplierFocus,
      'brokers' || 'broker' => ReportsLegacyFilterPreset.brokerFocus,
      'usage' => ReportsLegacyFilterPreset.usageOnly,
      _ => null,
    };
  }
}

enum ReportsLegacyFilterPreset {
  categoryFocus,
  subcategoryFocus,
  supplierFocus,
  brokerFocus,
  usageOnly,
}
