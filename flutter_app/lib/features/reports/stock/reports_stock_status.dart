import 'package:flutter/material.dart';

/// Warehouse movement classification for Reports → Stock tab.
enum ReportsStockMovementStatus {
  active,
  slow,
  verySlow,
  dead,
  fast,
  noActivity,
  outOfStock,
}

enum ReportsStockChipFilter {
  all,
  active,
  slow,
  dead,
  fast,
}

enum ReportsStockSort {
  highestStock,
  lowestStock,
  mostUsed,
  leastUsed,
  recentlyMoved,
  oldestMovement,
  az,
}

extension ReportsStockMovementStatusX on ReportsStockMovementStatus {
  static ReportsStockMovementStatus fromApi(String? raw) {
    return switch (raw) {
      'fast' => ReportsStockMovementStatus.fast,
      'slow' => ReportsStockMovementStatus.slow,
      'very_slow' => ReportsStockMovementStatus.verySlow,
      'dead' => ReportsStockMovementStatus.dead,
      'no_activity' => ReportsStockMovementStatus.noActivity,
      'out_of_stock' => ReportsStockMovementStatus.outOfStock,
      _ => ReportsStockMovementStatus.active,
    };
  }

  String get apiKey => switch (this) {
        ReportsStockMovementStatus.fast => 'fast',
        ReportsStockMovementStatus.slow => 'slow',
        ReportsStockMovementStatus.verySlow => 'very_slow',
        ReportsStockMovementStatus.dead => 'dead',
        ReportsStockMovementStatus.noActivity => 'no_activity',
        ReportsStockMovementStatus.outOfStock => 'out_of_stock',
        ReportsStockMovementStatus.active => 'active',
      };

  String get label => switch (this) {
        ReportsStockMovementStatus.active => 'Active',
        ReportsStockMovementStatus.slow => 'Slow Moving',
        ReportsStockMovementStatus.verySlow => 'Very Slow',
        ReportsStockMovementStatus.dead => 'Dead Stock',
        ReportsStockMovementStatus.fast => 'Fast Moving',
        ReportsStockMovementStatus.noActivity => 'No Activity',
        ReportsStockMovementStatus.outOfStock => 'Out of Stock',
      };

  Color get badgeBackground => switch (this) {
        ReportsStockMovementStatus.active => const Color(0xFFE8F5E0),
        ReportsStockMovementStatus.slow => const Color(0xFFFFF8E1),
        ReportsStockMovementStatus.verySlow => const Color(0xFFFFF3E0),
        ReportsStockMovementStatus.dead => const Color(0xFFFFEBEE),
        ReportsStockMovementStatus.fast => const Color(0xFFE3F2FD),
        ReportsStockMovementStatus.noActivity => const Color(0xFFF1F5F9),
        ReportsStockMovementStatus.outOfStock => const Color(0xFFF1F5F9),
      };

  Color get badgeForeground => switch (this) {
        ReportsStockMovementStatus.active => const Color(0xFF3B6D11),
        ReportsStockMovementStatus.slow => const Color(0xFFBA7517),
        ReportsStockMovementStatus.verySlow => const Color(0xFFE65100),
        ReportsStockMovementStatus.dead => const Color(0xFFA32D2D),
        ReportsStockMovementStatus.fast => const Color(0xFF1565C0),
        ReportsStockMovementStatus.noActivity => const Color(0xFF64748B),
        ReportsStockMovementStatus.outOfStock => const Color(0xFF64748B),
      };

  /// Left border accent on intel cards.
  Color get borderAccent => switch (this) {
        ReportsStockMovementStatus.active => const Color(0xFF4CAF50),
        ReportsStockMovementStatus.slow => const Color(0xFFFBC02D),
        ReportsStockMovementStatus.verySlow => const Color(0xFFFF9800),
        ReportsStockMovementStatus.dead => const Color(0xFFE53935),
        ReportsStockMovementStatus.fast => const Color(0xFF2196F3),
        ReportsStockMovementStatus.noActivity => const Color(0xFF94A3B8),
        ReportsStockMovementStatus.outOfStock => const Color(0xFFCBD5E1),
      };
}

extension ReportsStockChipFilterX on ReportsStockChipFilter {
  String get label => switch (this) {
        ReportsStockChipFilter.all => 'All',
        ReportsStockChipFilter.active => 'Active',
        ReportsStockChipFilter.slow => 'Slow',
        ReportsStockChipFilter.dead => 'Dead',
        ReportsStockChipFilter.fast => 'Fast',
      };

  static ReportsStockChipFilter? fromHighlight(String? section) {
    return switch (section) {
      'dead' => ReportsStockChipFilter.dead,
      'fast' => ReportsStockChipFilter.fast,
      'slow' => ReportsStockChipFilter.slow,
      'active' => ReportsStockChipFilter.active,
      _ => null,
    };
  }
}

extension ReportsStockSortX on ReportsStockSort {
  String get label => switch (this) {
        ReportsStockSort.highestStock => 'Highest stock',
        ReportsStockSort.lowestStock => 'Lowest stock',
        ReportsStockSort.mostUsed => 'Most used (7d)',
        ReportsStockSort.leastUsed => 'Least used (7d)',
        ReportsStockSort.recentlyMoved => 'Recently moved',
        ReportsStockSort.oldestMovement => 'Oldest movement',
        ReportsStockSort.az => 'A–Z',
      };
}
