import 'package:intl/intl.dart';

import '../../../core/models/trade_purchase_models.dart';
import '../../../core/reporting/trade_report_aggregate.dart';

String reportQtySummaryBoldLine(TradeReportItemRow r) {
  final parts = <String>[];
  if (r.kg > 1e-9) {
    final k = r.kg;
    final kTxt =
        (k - k.roundToDouble()).abs() < 1e-6 ? '${k.round()}' : k.toStringAsFixed(1);
    parts.add('$kTxt KG');
  }
  if (r.bags > 1e-9) {
    final q = r.bags;
    final qTxt =
        (q - q.roundToDouble()).abs() < 1e-6 ? '${q.round()}' : q.toStringAsFixed(1);
    parts.add('$qTxt BAGS');
  }
  if (r.boxes > 1e-9) {
    final q = r.boxes;
    final qTxt =
        (q - q.roundToDouble()).abs() < 1e-6 ? '${q.round()}' : q.toStringAsFixed(1);
    parts.add('$qTxt BOX');
  }
  if (r.tins > 1e-9) {
    final q = r.tins;
    final qTxt =
        (q - q.roundToDouble()).abs() < 1e-6 ? '${q.round()}' : q.toStringAsFixed(1);
    parts.add('$qTxt TIN');
  }
  return parts.join(' • ');
}

String _fmtRate(num? n) {
  if (n == null || n <= 0) return '—';
  return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
      .format(n);
}

/// Qty-weighted average purchase and selling rates (per line unit qty).
({double? buy, double? sell}) reportItemWeightedRates(
  List<TradePurchase> purchases,
  String itemKey,
) {
  var buyNum = 0.0;
  var sellNum = 0.0;
  var sellDen = 0.0;
  var w = 0.0;
  for (final p in purchases) {
    for (final l in p.lines) {
      final eff = reportEffectivePack(l);
      if (eff == null) continue;
      if (reportItemKey(l) != itemKey) continue;
      if (eff.packQty <= 1e-12) continue;
      final br = (l.purchaseRate != null && l.purchaseRate! > 0)
          ? l.purchaseRate!
          : l.landingCost;
      buyNum += br * eff.packQty;
      w += eff.packQty;
      final sr = l.sellingRate ?? l.sellingCost;
      if (sr != null && sr > 0) {
        sellNum += sr * eff.packQty;
        sellDen += eff.packQty;
      }
    }
  }
  if (w < 1e-9) return (buy: null, sell: null);
  final buy = buyNum / w;
  final sell = sellDen > 1e-9 ? sellNum / sellDen : null;
  return (buy: buy, sell: sell);
}

String reportItemRateArrowLine(List<TradePurchase> purchases, String itemKey) {
  final r = reportItemWeightedRates(purchases, itemKey);
  if ((r.buy == null || r.buy! <= 0) && (r.sell == null || r.sell! <= 0)) {
    return '';
  }
  return '${_fmtRate(r.buy)} → ${_fmtRate(r.sell)}';
}

class ReportItemTxnView {
  ReportItemTxnView({
    required this.date,
    required this.supplierName,
    required this.kg,
    required this.buyRate,
    required this.sellRate,
  });

  final DateTime date;
  final String supplierName;
  final double kg;
  final double buyRate;
  final double? sellRate;
}

List<ReportItemTxnView> reportItemTransactions(
  List<TradePurchase> purchases,
  String itemKey,
) {
  final out = <ReportItemTxnView>[];
  for (final p in purchases) {
    final sup = reportSupplierTitle(p);
    for (final l in p.lines) {
      final eff = reportEffectivePack(l);
      if (eff == null) continue;
      if (reportItemKey(l) != itemKey) continue;
      final kg = eff.kg;
      final br = (l.purchaseRate != null && l.purchaseRate! > 0)
          ? l.purchaseRate!
          : l.landingCost;
      final sr = l.sellingRate ?? l.sellingCost;
      out.add(
        ReportItemTxnView(
          date: p.purchaseDate,
          supplierName: sup,
          kg: kg,
          buyRate: br,
          sellRate: sr,
        ),
      );
    }
  }
  out.sort((a, b) {
    final c = b.date.compareTo(a.date);
    if (c != 0) return c;
    return a.supplierName.compareTo(b.supplierName);
  });
  return out;
}
