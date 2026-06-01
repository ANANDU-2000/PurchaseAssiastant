import '../../../core/json_coerce.dart';
import 'reports_stock_status.dart';

class ReportsStockSummary {
  const ReportsStockSummary({
    this.all = 0,
    this.active = 0,
    this.slow = 0,
    this.dead = 0,
    this.fast = 0,
    this.noActivity = 0,
  });

  final int all;
  final int active;
  final int slow;
  final int dead;
  final int fast;
  final int noActivity;

  factory ReportsStockSummary.fromMap(Map<String, dynamic>? raw) {
    if (raw == null) return const ReportsStockSummary();
    int n(String k) =>
        raw[k] is int ? raw[k] as int : int.tryParse('${raw[k]}') ?? 0;
    return ReportsStockSummary(
      all: n('all'),
      active: n('active'),
      slow: n('slow'),
      dead: n('dead'),
      fast: n('fast'),
      noActivity: n('no_activity'),
    );
  }

  int countFor(ReportsStockChipFilter filter) => switch (filter) {
        ReportsStockChipFilter.all => all,
        ReportsStockChipFilter.active => active,
        ReportsStockChipFilter.slow => slow,
        ReportsStockChipFilter.dead => dead,
        ReportsStockChipFilter.fast => fast,
      };
}

class ReportsStockIntelItem {
  const ReportsStockIntelItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.currentStock,
    required this.used7d,
    required this.used30d,
    required this.idleDays,
    required this.status,
    this.itemCode,
    this.lastMovementAt,
  });

  final String id;
  final String name;
  final String? itemCode;
  final String category;
  final String unit;
  final double currentStock;
  final double used7d;
  final double used30d;
  final int idleDays;
  final ReportsStockMovementStatus status;
  final String? lastMovementAt;

  factory ReportsStockIntelItem.fromMap(Map<String, dynamic> raw) {
    final idle = raw['idle_days'] is int
        ? raw['idle_days'] as int
        : int.tryParse('${raw['idle_days']}') ?? 999;
    return ReportsStockIntelItem(
      id: raw['id']?.toString() ?? '',
      name: raw['name']?.toString() ?? '—',
      itemCode: raw['item_code']?.toString(),
      category: raw['category']?.toString() ?? '',
      unit: raw['unit']?.toString() ?? '',
      currentStock: coerceToDouble(raw['current_stock']),
      used7d: coerceToDouble(raw['used_7d']),
      used30d: coerceToDouble(raw['used_30d']),
      idleDays: idle,
      status: ReportsStockMovementStatusX.fromApi(
        raw['movement_status']?.toString(),
      ),
      lastMovementAt: raw['last_movement_at']?.toString(),
    );
  }

  bool matchesChip(ReportsStockChipFilter chip) {
    if (chip == ReportsStockChipFilter.all) {
      return currentStock > 0;
    }
    return status.matchesChipForItem(chip);
  }

  String get movementLabel {
    if (idleDays >= 999) return 'No movement recorded';
    if (idleDays == 0) return 'Today';
    if (idleDays == 1) return '1 day ago';
    return '$idleDays days ago';
  }

  String get movementCompact {
    if (idleDays >= 999) return 'No movement';
    if (idleDays == 0) return 'Today';
    return '${idleDays}d ago';
  }
}

extension _StatusChipMatch on ReportsStockMovementStatus {
  bool matchesChipForItem(ReportsStockChipFilter chip) => switch (chip) {
        ReportsStockChipFilter.all => true,
        ReportsStockChipFilter.active =>
          this == ReportsStockMovementStatus.active,
        ReportsStockChipFilter.slow =>
          this == ReportsStockMovementStatus.slow ||
              this == ReportsStockMovementStatus.verySlow,
        ReportsStockChipFilter.dead => this == ReportsStockMovementStatus.dead,
        ReportsStockChipFilter.fast => this == ReportsStockMovementStatus.fast,
      };
}
