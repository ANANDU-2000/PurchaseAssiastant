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

/// Kg-weighted average **₹/kg** purchase and selling rates for the item key.
///
/// Using [TradePurchaseLine.landingGross] / kg avoids bag lines showing
/// ₹1,300→₹1,350 when economics are ₹26→₹27/kg.
({double? buy, double? sell}) reportItemWeightedRates(
  List<TradePurchase> purchases,
  String itemKey,
) {
  var totalKgBuy = 0.0;
  var totalLanding = 0.0;
  var totalKgSell = 0.0;
  var totalSelling = 0.0;
  for (final p in purchases) {
    for (final l in p.lines) {
      final eff = reportEffectivePack(l);
      if (eff == null) continue;
      if (reportItemKey(l) != itemKey) continue;
      final kg = eff.kg;
      if (kg <= 1e-9) continue;
      final lg = l.landingGross;
      if (lg > 1e-9) {
        totalLanding += lg;
        totalKgBuy += kg;
      }
      final sg = l.sellingGross;
      if (sg > 1e-9) {
        totalSelling += sg;
        totalKgSell += kg;
      }
    }
  }
  if (totalKgBuy < 1e-9) return (buy: null, sell: null);
  final buy = totalLanding / totalKgBuy;
  final sell = totalKgSell > 1e-9 ? totalSelling / totalKgSell : null;
  return (buy: buy, sell: sell);
}

String reportItemRateArrowLine(List<TradePurchase> purchases, String itemKey) {
  final r = reportItemWeightedRates(purchases, itemKey);
  final buyS = (r.buy != null && r.buy! > 0) ? '${_fmtRate(r.buy)}/kg' : '—';
  final sellS = (r.sell != null && r.sell! > 0) ? '${_fmtRate(r.sell)}/kg' : '—';
  if (buyS == '—' && sellS == '—') return '';
  return '$buyS → $sellS';
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
      final br = kg > 1e-9 ? l.landingGross / kg : 0.0;
      final sg = l.sellingGross;
      final sr = (sg > 1e-9 && kg > 1e-9) ? sg / kg : null;
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
