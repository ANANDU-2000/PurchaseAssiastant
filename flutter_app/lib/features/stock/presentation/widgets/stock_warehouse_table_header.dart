import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_responsive.dart';
import 'stock_table_layout.dart';

/// Warehouse table header — responsive columns:
/// Mobile:  ITEM | SYS | PHYS | DIFF
/// Tablet+: ITEM | SYS | PHYS | DIFF | PENDING | STATUS
///
/// Spec columns: Item, System Stock, Physical Stock, Difference,
///               Pending Delivery, Status, Last Updated, Verified By
/// (Last Updated + Verified By shown in row meta line on mobile,
///  as dedicated columns on desktop.)
class StockWarehouseTableHeader extends StatelessWidget {
  const StockWarehouseTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final hdr = HexaDsType.label(9).copyWith(
      fontWeight: FontWeight.w800,
      color: const Color(0xFF475569),
      letterSpacing: 0.2,
      height: 1.15,
    );
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: HexaResponsive.pageGutter(context, operational: true),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: StockTableLayout.headerFill,
          border: Border.all(color: StockTableLayout.borderColor),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: StockTableLayout.itemCellDecoration(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: StockTableLayout.cellHPadding,
                    vertical: 6,
                  ),
                  alignment: Alignment.centerLeft,
                  child: Text('ITEM', style: hdr),
                ),
              ),
              _metricHeader(
                'SYS',
                hdr,
                tooltip:
                    'System Stock — warehouse ledger quantity (opening + verified deliveries - sales - damages - usage)',
              ),
              _metricHeader(
                'PHYS',
                hdr,
                tooltip: 'Physical Stock — last warehouse floor count',
              ),
              _metricHeader(
                'DIFF',
                hdr,
                tooltip: 'Difference — System minus Physical (positive = excess, negative = deficit)',
              ),
              if (isWide)
                _metricHeader(
                  'PEND',
                  hdr,
                  tooltip: 'Pending Delivery — unverified purchase quantities in transit',
                ),
              if (isWide)
                _metricHeader(
                  'STATUS',
                  hdr,
                  tooltip: 'Stock Status — Healthy / Low / Critical / Out',
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricHeader(String label, TextStyle style, {String? tooltip}) {
    final cell = Container(
      width: StockTableLayout.metricColWidth,
      decoration: StockTableLayout.cellDecoration(),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Text(label, style: style, textAlign: TextAlign.center),
    );
    if (tooltip == null || tooltip.isEmpty) return cell;
    return Tooltip(message: tooltip, child: cell);
  }
}
