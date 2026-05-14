import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/calc_engine.dart' show lineMoney;
import '../../core/catalog/item_trade_history.dart' show tradeLineToCalc;
import '../../core/models/trade_purchase_models.dart';
import '../../core/reporting/trade_report_aggregate.dart';
import '../../core/utils/line_display.dart';
import '../../core/utils/trade_purchase_rate_display.dart';

double lineKgEstimate(TradePurchaseLine ln) {
  if (ln.totalWeight != null && ln.totalWeight! > 0) return ln.totalWeight!;
  final u = ln.unit.trim().toLowerCase();
  if (u == 'kg' ||
      u == 'kgs' ||
      u == 'kilogram' ||
      u == 'kilograms' ||
      u == 'quintal' ||
      u == 'qtl') {
    return ln.qty;
  }
  // Only non-kg lines may use kg_per_unit as a weight hint.
  final kpu = ln.kgPerUnit;
  if (kpu != null && kpu > 0) return ln.qty * kpu;
  return 0;
}

double lineAmountInr(TradePurchaseLine ln) =>
    ln.lineTotal ?? lineMoney(tradeLineToCalc(ln));

bool defaultActiveBill(TradePurchase p) =>
    p.statusEnum != PurchaseStatus.draft &&
    p.statusEnum != PurchaseStatus.cancelled;

typedef PurchaseInclusion = bool Function(TradePurchase p);

({int bills, double spend, double unpaid, double kg}) ledgerMoneyKgTotals(
  List<TradePurchase> trades, {
  PurchaseInclusion include = defaultActiveBill,
}) {
  var bills = 0;
  double spend = 0, unpaid = 0, kg = 0;
  for (final p in trades) {
    if (!include(p)) continue;
    bills++;
    spend += p.totalAmount;
    unpaid += p.remaining;
    for (final ln in p.lines) {
      kg += lineKgEstimate(ln);
    }
  }
  return (bills: bills, spend: spend, unpaid: unpaid, kg: kg);
}

/// Unit-ish counts where the purchase unit label suggests discrete containers.
({double bags, double boxes, double tins}) ledgerContainerHints(
    List<TradePurchase> trades,
    {PurchaseInclusion include = defaultActiveBill}) {
  double bags = 0, boxes = 0, tins = 0;
  for (final p in trades) {
    if (!include(p)) continue;
    for (final ln in p.lines) {
      final u = ln.unit.trim().toLowerCase();
      if (u.contains('bag')) bags += ln.qty;
      if (u.contains('box')) boxes += ln.qty;
      if (u.contains('tin')) tins += ln.qty;
    }
  }
  return (bags: bags, boxes: boxes, tins: tins);
}

/// Summary chips for bills, ₹, kg (narrow-friendly).
class TradeLedgerSummaryStrip extends StatelessWidget {
  const TradeLedgerSummaryStrip({
    super.key,
    required this.bills,
    required this.inrSpend,
    required this.kg,
    this.bags,
    this.boxes,
    this.tins,
    this.subtitle,
  });

  final int bills;
  final String inrSpend;
  final double kg;
  final double? bags;
  final double? boxes;
  final double? tins;
  final String? subtitle;

  String _fmtKg(double v) {
    if (v <= 0) return '—';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(2)} t';
    if (v == v.roundToDouble()) return '${v.round()} kg';
    return '${v.toStringAsFixed(1)} kg';
  }

  String? _extras() {
    final parts = <String>[];
    final b = bags ?? 0, bx = boxes ?? 0, t = tins ?? 0;
    if (b > 0) parts.add(b == b.roundToDouble() ? '${b.round()} bags' : '${b.toStringAsFixed(1)} bags');
    if (bx > 0) parts.add(bx == bx.roundToDouble() ? '${bx.round()} boxes' : '${bx.toStringAsFixed(1)} boxes');
    if (t > 0) parts.add(t == t.roundToDouble() ? '${t.round()} tins' : '${t.toStringAsFixed(1)} tins');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final extras = _extras();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              Text(
                subtitle!,
                style: tt.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _ChipStat(label: 'Bills', value: '$bills'),
                _ChipStat(label: 'Total amount', value: inrSpend),
                _ChipStat(label: 'Est. kg', value: _fmtKg(kg)),
              ],
            ),
            if (extras != null) ...[
              const SizedBox(height: 8),
              Text(
                extras,
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChipStat extends StatelessWidget {
  const _ChipStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class TradeLedgerCardList extends StatelessWidget {
  const TradeLedgerCardList({
    super.key,
    required this.trades,
    required this.useCompactLines,
    this.emptyHint,
    this.showBillTotals = false,
  });

  final List<TradePurchase> trades;
  final bool useCompactLines;
  final String? emptyHint;
  final bool showBillTotals;

  String _inr(num v) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: 0,
      ).format(v);

  String _rateP(TradePurchaseLine ln) {
    final r = tradePurchaseLineDisplayPurchaseRate(ln);
    final suffix = ledgerPurchaseRateDisplayDim(ln);
    return 'P:${_inr(r)}/$suffix';
  }

  String? _rateS(TradePurchaseLine ln) {
    final r = tradePurchaseLineDisplaySellingRate(ln);
    if (r == null) return null;
    final suffix = ledgerSellingRateDisplayDim(ln);
    return 'S:${_inr(r)}/$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat.yMMMd();

    if (trades.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          emptyHint ?? 'Nothing in this view.',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: trades.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, indent: 12, endIndent: 12),
        itemBuilder: (context, ip) {
          final p = trades[ip];
          String? totalsLine;
          if (showBillTotals) {
            var kg = 0.0, bags = 0.0, boxes = 0.0, tins = 0.0;
            for (final ln in p.lines) {
              kg += lineKgEstimate(ln);
              final eff = reportEffectivePack(ln);
              if (eff != null) {
                switch (eff.kind) {
                  case ReportPackKind.bag:
                    bags += eff.packQty;
                  case ReportPackKind.box:
                    boxes += eff.packQty;
                  case ReportPackKind.tin:
                    tins += eff.packQty;
                }
              } else {
                final u = ln.unit.trim().toLowerCase();
                if (u.contains('bag') || u.contains('sack')) bags += ln.qty;
                if (u.contains('box')) boxes += ln.qty;
                if (u.contains('tin')) tins += ln.qty;
              }
            }
            final parts = <String>[];
            if (kg > 1e-9) {
              parts.add(kg == kg.roundToDouble()
                  ? '${kg.round()} kg'
                  : '${kg.toStringAsFixed(1)} kg');
            }
            if (bags > 1e-9) {
              parts.add(bags == bags.roundToDouble()
                  ? '${bags.round()} bags'
                  : '${bags.toStringAsFixed(1)} bags');
            }
            if (boxes > 1e-9) {
              parts.add(boxes == boxes.roundToDouble()
                  ? '${boxes.round()} boxes'
                  : '${boxes.toStringAsFixed(1)} boxes');
            }
            if (tins > 1e-9) {
              parts.add(tins == tins.roundToDouble()
                  ? '${tins.round()} tins'
                  : '${tins.toStringAsFixed(1)} tins');
            }
            totalsLine = parts.isEmpty ? null : parts.join(' · ');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  p.humanId,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${fmt.format(p.purchaseDate)} · ${p.derivedStatus}'
                  '${(p.brokerName ?? '').isNotEmpty ? ' · ${p.brokerName}' : ''}'
                  '${totalsLine != null ? '\n$totalsLine' : ''}',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                trailing: Text(
                  _inr(p.totalAmount.round()),
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                onTap: () => context.push(
                      '/purchase/detail/${p.id}',
                      extra: p,
                    ),
              ),
              if (p.lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'No line items',
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              else
                Padding(
                  padding:
                      EdgeInsets.fromLTRB(useCompactLines ? 12 : 12, 0, 12, 10),
                  child: Column(
                    children: [
                      for (final ln in p.lines)
                        useCompactLines
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  onTap: () =>
                                      context.push(
                                        '/purchase/detail/${p.id}',
                                        extra: p,
                                      ),
                                  borderRadius: BorderRadius.circular(8),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: cs.surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            ln.itemName,
                                            style:
                                                tt.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                formatLineQtyWeightFromTradeLine(
                                                    ln),
                                                style: tt.labelSmall,
                                              ),
                                              Text(
                                                _rateP(ln),
                                                style: tt.labelSmall?.copyWith(
                                                    color:
                                                        cs.onSurfaceVariant),
                                              ),
                                              if (_rateS(ln) != null)
                                                Text(
                                                  _rateS(ln)!,
                                                  style:
                                                      tt.labelSmall?.copyWith(
                                                          color: cs
                                                              .onSurfaceVariant),
                                                ),
                                              Text(
                                                _inr(lineAmountInr(ln).round()),
                                                style:
                                                    tt.labelSmall?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  color: cs.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        ln.itemName,
                                        style: tt.bodySmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        formatLineQtyWeightFromTradeLine(ln),
                                        textAlign: TextAlign.right,
                                        style: tt.labelSmall,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _rateP(ln),
                                        textAlign: TextAlign.right,
                                        style: tt.labelSmall?.copyWith(
                                            color: cs.onSurfaceVariant),
                                      ),
                                    ),
                                    if (_rateS(ln) != null) ...[
                                      const SizedBox(width: 4),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          _rateS(ln)!,
                                          textAlign: TextAlign.right,
                                          style: tt.labelSmall?.copyWith(
                                              color: cs.onSurfaceVariant),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 4),
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        _inr(lineAmountInr(ln).round()),
                                        textAlign: TextAlign.right,
                                        style: tt.labelSmall?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
