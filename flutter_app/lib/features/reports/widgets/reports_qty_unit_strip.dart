import 'package:flutter/material.dart';

import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_utils.dart';

/// Compact bag / box / tin / kg breakdown for Reports overview.
class ReportsQtyUnitStrip extends StatelessWidget {
  const ReportsQtyUnitStrip({
    super.key,
    required this.bags,
    required this.boxes,
    required this.tins,
    required this.kg,
  });

  final double bags;
  final double boxes;
  final double tins;
  final double kg;

  static const _bagColor = Color(0xFF0D9488);
  static const _boxColor = Color(0xFF2563EB);
  static const _tinColor = Color(0xFFD97706);
  static const _kgColor = Color(0xFF7C3AED);

  @override
  Widget build(BuildContext context) {
    final cells = <_UnitCell>[
      if (bags > 0.001)
        _UnitCell('Bags', formatStockQtyForUnit('bag', bags), _bagColor),
      if (boxes > 0.001)
        _UnitCell('Boxes', formatStockQtyForUnit('box', boxes), _boxColor),
      if (tins > 0.001)
        _UnitCell('Tins', formatStockQtyForUnit('tin', tins), _tinColor),
      if (kg > 0.001)
        _UnitCell('Kg', formatStockQtyForUnit('kg', kg), _kgColor),
    ];
    if (cells.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: _UnitTile(cell: cells[i])),
        ],
      ],
    );
  }
}

class _UnitCell {
  const _UnitCell(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.cell});
  final _UnitCell cell;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: HexaColors.brandCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cell.color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            cell.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: cell.color.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            cell.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: cell.color,
            ),
          ),
        ],
      ),
    );
  }
}
