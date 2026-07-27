import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/calc_engine.dart';
import '../../../core/strict_decimal.dart';
import 'purchase_draft_provider.dart';
import 'purchase_trade_preview_provider.dart';

/// Header qty / grand amount: prefers debounced `preview-lines` when available.
final purchaseTotalsProvider = Provider<TradeCalcTotals>((ref) {
  final snap = ref.watch(tradePurchasePreviewProvider);
  final server = snap.asData?.value;
  if (server != null &&
      server['total_qty'] != null &&
      server['total_amount'] != null) {
    return TradeCalcTotals(
      qtySum: StrictDecimal.fromObject(server['total_qty']!).toDouble(),
      amountSum: StrictDecimal.fromObject(server['total_amount']!).toDouble(),
    );
  }
  ref.watch(
    purchaseDraftProvider.select(
      (d) => (
        lines: d.lines,
        headerDiscountPercent: d.headerDiscountPercent,
        commissionMode: d.commissionMode,
        commissionPercent: d.commissionPercent,
        commissionMoney: d.commissionMoney,
        freightAmount: d.freightAmount,
        freightType: d.freightType,
        billtyRate: d.billtyRate,
        deliveredRate: d.deliveredRate,
      ),
    ),
  );
  final d = ref.read(purchaseDraftProvider);
  return computePurchaseTotals(d);
});
