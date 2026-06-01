import 'package:flutter/material.dart';

import '../../../../core/theme/hexa_colors.dart';
import '../../../../core/widgets/hexa_count_badge.dart';

/// Owner dashboard quick actions (2×4 grid, ~56dp tiles).
class HomeOwnerQuickActions extends StatelessWidget {
  const HomeOwnerQuickActions({
    super.key,
    required this.onStock,
    required this.onPurchase,
    required this.onLowStock,
    required this.onDelivered,
    required this.onReports,
    required this.onUsers,
    required this.onBarcode,
    required this.onReorder,
    required this.onDailyLog,
    this.lowStockCount = 0,
  });

  final VoidCallback onStock;
  final VoidCallback onPurchase;
  final VoidCallback onLowStock;
  final VoidCallback onDelivered;
  final VoidCallback onReports;
  final VoidCallback onUsers;
  final VoidCallback onBarcode;
  final VoidCallback onReorder;
  final VoidCallback onDailyLog;
  final int lowStockCount;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _Spec('Purchase', Icons.add_shopping_cart_rounded, HexaColors.brandPrimary, onPurchase),
      _Spec('Stock', Icons.inventory_2_rounded, const Color(0xFF1565C0), onStock),
      _Spec('Low stock', Icons.warning_amber_rounded, HexaColors.warning, onLowStock, badge: lowStockCount),
      _Spec('Delivered', Icons.check_circle_outline_rounded, HexaColors.profit, onDelivered),
      _Spec('Reports', Icons.bar_chart_rounded, const Color(0xFF0D9488), onReports),
      _Spec('Users', Icons.group_rounded, const Color(0xFF5D4037), onUsers),
      _Spec('Barcode', Icons.qr_code_2_rounded, const Color(0xFF455A64), onBarcode),
      _Spec('Reorder', Icons.autorenew_rounded, const Color(0xFF7C3AED), onReorder),
      _Spec('Daily log', Icons.history_rounded, const Color(0xFF0D9488), onDailyLog),
    ];

    final cols = MediaQuery.sizeOf(context).width < 360 ? 3 : 4;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tools',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 8),
        GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: cols == 3 ? 1.1 : 1.35,
      children: [
        for (final a in actions) _Tile(spec: a),
      ],
    ),
      ],
    );
  }
}

class _Spec {
  const _Spec(this.label, this.icon, this.color, this.onTap, {this.badge});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int? badge;
}

class _Tile extends StatelessWidget {
  const _Tile({required this.spec});
  final _Spec spec;

  @override
  Widget build(BuildContext context) {
    final badge = spec.badge;
    return Material(
      color: spec.color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: spec.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              HexaCountBadge(
                count: badge,
                maxDisplay: 999,
                child: Icon(spec.icon, color: spec.color, size: 22),
              ),
              const SizedBox(height: 4),
              Text(
                spec.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: spec.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
