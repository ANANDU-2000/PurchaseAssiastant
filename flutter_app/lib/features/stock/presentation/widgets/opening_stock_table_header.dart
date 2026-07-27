import 'package:flutter/material.dart';

import '../../../../core/design_system/hexa_responsive.dart';
import 'stock_table_layout.dart';

/// Opening stock table header: ITEM | UNIT | OPENING | STATUS.
class OpeningStockTableHeader extends StatelessWidget {
  const OpeningStockTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final hdr = const TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      color: Color(0xFF475569),
      letterSpacing: 0.3,
    );

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
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Text('ITEM', style: hdr),
                ),
              ),
              Container(
                width: 60,
                decoration: StockTableLayout.cellDecoration(),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('UNIT', style: hdr, textAlign: TextAlign.center),
              ),
              Container(
                width: 90,
                decoration: StockTableLayout.cellDecoration(),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('OPENING', style: hdr, textAlign: TextAlign.center),
              ),
              Container(
                width: 90,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('STATUS', style: hdr, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

