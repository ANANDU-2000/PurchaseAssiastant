import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';
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
        ReportsStockMovementStatus.active => HexaColors.statusActiveBg,
        ReportsStockMovementStatus.slow => HexaColors.statusSlowBg,
        ReportsStockMovementStatus.verySlow => HexaColors.statusVerySlowBg,
        ReportsStockMovementStatus.dead => HexaColors.statusDeadBg,
        ReportsStockMovementStatus.fast => HexaColors.statusFastBg,
        ReportsStockMovementStatus.noActivity => HexaColors.slate100,
        ReportsStockMovementStatus.outOfStock => HexaColors.slate100,
      };

  Color get badgeForeground => switch (this) {
        ReportsStockMovementStatus.active => HexaColors.statusActiveFg,
        ReportsStockMovementStatus.slow => HexaColors.statusSlowFg,
        ReportsStockMovementStatus.verySlow => HexaColors.accentOrange,
        ReportsStockMovementStatus.dead => HexaColors.dangerDeep,
        ReportsStockMovementStatus.fast => HexaColors.materialBlue,
        ReportsStockMovementStatus.noActivity => HexaColors.neutral,
        ReportsStockMovementStatus.outOfStock => HexaColors.neutral,
      };

  /// Left border accent on intel cards.
  Color get borderAccent => switch (this) {
        ReportsStockMovementStatus.active => HexaColors.statusActiveBorder,
        ReportsStockMovementStatus.slow => HexaColors.statusSlowBorder,
        ReportsStockMovementStatus.verySlow => HexaColors.statusVerySlowBorder,
        ReportsStockMovementStatus.dead => HexaColors.loss,
        ReportsStockMovementStatus.fast => HexaColors.statusFastBorder,
        ReportsStockMovementStatus.noActivity => HexaColors.cost,
        ReportsStockMovementStatus.outOfStock => HexaColors.slate300,
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
