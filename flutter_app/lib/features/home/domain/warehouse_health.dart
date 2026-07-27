/// Client-side warehouse health score for owner dashboard.
enum WarehouseHealthLevel { good, warning, critical }

class WarehouseHealthInput {
  const WarehouseHealthInput({
    this.criticalStock = 0,
    this.lowStock = 0,
    this.mismatchCount = 0,
    this.negativeStock = 0,
    this.pendingDeliveries = 0,
    this.pendingApprovals = 0,
    this.criticalAlerts = 0,
  });

  final int criticalStock;
  final int lowStock;
  final int mismatchCount;
  final int negativeStock;
  final int pendingDeliveries;
  final int pendingApprovals;
  final int criticalAlerts;
}

WarehouseHealthLevel computeWarehouseHealth(WarehouseHealthInput input) {
  if (input.criticalStock > 0 ||
      input.mismatchCount > 0 ||
      input.negativeStock > 0 ||
      input.criticalAlerts > 0) {
    return WarehouseHealthLevel.critical;
  }
  if (input.lowStock > 0 ||
      input.pendingDeliveries > 0 ||
      input.pendingApprovals > 0) {
    return WarehouseHealthLevel.warning;
  }
  return WarehouseHealthLevel.good;
}

String warehouseHealthLabel(WarehouseHealthLevel level) => switch (level) {
      WarehouseHealthLevel.good => 'GOOD',
      WarehouseHealthLevel.warning => 'WARNING',
      WarehouseHealthLevel.critical => 'CRITICAL',
    };
