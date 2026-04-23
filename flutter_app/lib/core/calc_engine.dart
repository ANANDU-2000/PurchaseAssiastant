/// One line of a trade purchase (API-aligned field names).
/// Totals: use [computeTradeTotals] — mirrors backend `trade_purchase_service`.
class TradeCalcLine {
  const TradeCalcLine({
    required this.qty,
    required this.landingCost,
    this.discountPercent,
    this.taxPercent,
  });

  final double qty;
  final double landingCost;
  /// Line discount 0–100 (%), same semantics as backend.
  final double? discountPercent;
  final double? taxPercent;
}

class TradeCalcRequest {
  const TradeCalcRequest({
    required this.lines,
    this.headerDiscountPercent,
    this.commissionPercent,
    this.freightAmount,
    this.freightType,
  });

  final List<TradeCalcLine> lines;
  final double? headerDiscountPercent;
  final double? commissionPercent;
  final double? freightAmount;
  /// `separate` adds freight; `included` ignores [freightAmount] for totals.
  final String? freightType;
}

class TradeCalcTotals {
  const TradeCalcTotals({
    required this.qtySum,
    required this.amountSum,
  });

  final double qtySum;
  final double amountSum;
}

double _dec(double? x) => x ?? 0.0;

/// Per-line amount after line discount and tax multiplier (matches backend).
double lineMoney(TradeCalcLine li) {
  final base = _dec(li.qty) * _dec(li.landingCost);
  final ld = li.discountPercent != null ? _dec(li.discountPercent) : 0.0;
  final afterDisc = base * (1.0 - (ld > 100 ? 100 : ld) / 100.0);
  final tax = li.taxPercent != null ? _dec(li.taxPercent) : 0.0;
  final t = tax > 1000 ? 1000.0 : tax;
  return afterDisc * (1.0 + t / 100.0);
}

/// Returns total quantity sum and final amount (matches backend `compute_totals`).
TradeCalcTotals computeTradeTotals(TradeCalcRequest req) {
  var qtySum = 0.0;
  var amtSum = 0.0;
  for (final li in req.lines) {
    qtySum += _dec(li.qty);
    amtSum += lineMoney(li);
  }

  final headerDisc =
      req.headerDiscountPercent != null ? _dec(req.headerDiscountPercent) : 0.0;
  var afterHeader = amtSum;
  if (headerDisc > 0) {
    final hd = headerDisc > 100 ? 100.0 : headerDisc;
    afterHeader = amtSum * (1.0 - hd / 100.0);
  }
  amtSum = afterHeader;

  var freight = req.freightAmount != null ? _dec(req.freightAmount) : 0.0;
  if (req.freightType == 'included') {
    freight = 0.0;
  }
  amtSum += freight;

  final comm =
      req.commissionPercent != null ? _dec(req.commissionPercent) : 0.0;
  if (comm > 0) {
    final c = comm > 100 ? 100.0 : comm;
    amtSum += afterHeader * c / 100.0;
  }

  return TradeCalcTotals(qtySum: qtySum, amountSum: amtSum);
}
