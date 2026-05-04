import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/calc_engine.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidatePurchaseWorkspace;
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/services/purchase_invoice_pdf_layout.dart'
    show tradeCalcRequestFromTradePurchase;
import '../../../core/services/purchase_pdf.dart';
import '../../../core/utils/trade_purchase_commission.dart';
import '../../../core/utils/trade_purchase_rate_display.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/unit_classifier.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';

final _purchaseDetailProvider = FutureProvider.autoDispose
    .family<TradePurchase, String>((ref, purchaseId) async {
  final session = ref.watch(sessionProvider);
  if (session == null) throw StateError('no session');
  final m = await ref.read(hexaApiProvider).getTradePurchase(
        businessId: session.primaryBusiness.id,
        purchaseId: purchaseId,
      );
  return TradePurchase.fromJson(m);
});

String _inr(num n, {int fractionDigits = 2}) =>
    NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: fractionDigits,
    ).format(n);

String _qtyFmt(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(2);

double _lineInclusive(TradePurchaseLine l) {
  return lineMoney(
    TradeCalcLine(
      qty: l.qty,
      landingCost: l.landingCost,
      kgPerUnit: l.kgPerUnit,
      landingCostPerKg: l.landingCostPerKg,
      taxPercent: l.taxPercent,
      discountPercent: l.discount,
    ),
  );
}

double _lineKg(TradePurchaseLine l) {
  return ledgerTradeLineWeightKg(
    itemName: l.itemName,
    unit: l.unit,
    qty: l.qty,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
    kgPerUnit: l.kgPerUnit,
    boxMode: l.boxMode,
    itemsPerBox: l.itemsPerBox,
    weightPerItem: l.weightPerItem,
    kgPerBox: l.kgPerBox,
    weightPerTin: l.weightPerTin,
  );
}

String _unitClassificationHint(TradePurchaseLine l) {
  final clf = UnitClassifier.classify(
    itemName: l.itemName,
    lineUnit: l.unit,
    catalogDefaultUnit: l.defaultPurchaseUnit ?? l.defaultUnit,
    catalogDefaultKgPerBag: l.defaultKgPerBag,
  );
  return switch (clf.type) {
    UnitType.weightBag => 'Class: weight bag',
    UnitType.singlePack => clf.kgFromName != null && clf.kgFromName! > 0
        ? 'Class: single pack (${clf.kgFromName} kg)'
        : 'Class: single pack',
    UnitType.multiPackBox => 'Class: multi-pack box',
  };
}

double? _effectiveLineProfit(TradePurchaseLine l) {
  if (l.lineProfit != null) return l.lineProfit;
  final hasSell = (l.sellingRate ?? l.sellingCost) != null;
  if (!hasSell) return null;
  return l.sellingGross - l.landingGross;
}

class _Agg {
  const _Agg({
    required this.linesInclusive,
    required this.afterHeaderDiscount,
    required this.discountRupeeEffect,
    required this.headerDiscountPct,
    required this.freight,
    required this.freightIncluded,
    required this.commission,
    required this.billty,
    required this.delivered,
    required this.finalComputed,
    required this.totalKg,
    required this.totalBags,
    required this.totalBox,
    required this.totalTin,
    required this.sumLandingGross,
    required this.sumSellingGross,
    required this.sumProfit,
  });

  final double linesInclusive;
  final double afterHeaderDiscount;
  final double discountRupeeEffect;
  final double headerDiscountPct;
  final double freight;
  final bool freightIncluded;
  final double commission;
  final double billty;
  final double delivered;
  final double finalComputed;
  final double totalKg;
  final double totalBags;
  final double totalBox;
  final double totalTin;
  final double sumLandingGross;
  final double sumSellingGross;
  final double sumProfit;
}

_Agg _buildAgg(TradePurchase p) {
  var linesInclusive = 0.0;
  var sumLandingGross = 0.0;
  var sumSellingGross = 0.0;
  var profitSum = 0.0;
  var kg = 0.0;
  var bags = 0.0;
  var boxes = 0.0;
  var tins = 0.0;

  for (final l in p.lines) {
    linesInclusive += _lineInclusive(l);
    sumLandingGross += l.landingGross;
    sumSellingGross += l.sellingGross;
    final pr = _effectiveLineProfit(l);
    if (pr != null) profitSum += pr;
    kg += _lineKg(l);
    final u = l.unit.trim().toLowerCase();
    if (u == 'bag' || u == 'sack') {
      bags += l.qty;
    } else if (u == 'box') {
      boxes += l.qty;
    } else if (u == 'tin') {
      tins += l.qty;
    }
  }

  if (p.totalLineProfit != null) {
    profitSum = p.totalLineProfit!;
  }

  final req = tradeCalcRequestFromTradePurchase(p);
  final totals = computeTradeTotals(req);
  final hdr = p.discount ?? 0.0;
  final clippedHdr = hdr > 100 ? 100.0 : (hdr < 0 ? 0.0 : hdr);
  final afterHd = clippedHdr <= 0
      ? linesInclusive
      : linesInclusive - linesInclusive * (clippedHdr / 100);

  final included = req.freightType == 'included';
  final fr = req.freightAmount != null && req.freightAmount! > 0 && !included
      ? req.freightAmount!
      : 0.0;

  return _Agg(
    linesInclusive: linesInclusive,
    afterHeaderDiscount: afterHd,
    discountRupeeEffect: linesInclusive - afterHd,
    headerDiscountPct: clippedHdr,
    freight: fr,
    freightIncluded: included,
    commission: tradePurchaseCommissionInr(p),
    billty: req.billtyRate ?? 0.0,
    delivered: req.deliveredRate ?? 0.0,
    finalComputed: totals.amountSum,
    totalKg: kg,
    totalBags: bags,
    totalBox: boxes,
    totalTin: tins,
    sumLandingGross: sumLandingGross,
    sumSellingGross: sumSellingGross,
    sumProfit: profitSum,
  );
}

class PurchaseDetailPage extends ConsumerWidget {
  const PurchaseDetailPage({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_purchaseDetailProvider(purchaseId));
    return async.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.popOrGo('/purchase'),
          ),
          title: const Text('Purchase'),
          backgroundColor: Colors.transparent,
          foregroundColor: HexaColors.brandPrimary,
        ),
        body: const DetailSkeleton(),
      ),
      error: (_, __) => Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.popOrGo('/purchase'),
          ),
          title: const Text('Purchase'),
          backgroundColor: Colors.transparent,
          foregroundColor: HexaColors.brandPrimary,
        ),
        body: FriendlyLoadError(
          message: "Couldn't load purchase",
          onRetry: () => ref.invalidate(_purchaseDetailProvider(purchaseId)),
        ),
      ),
      data: (p) => _LoadedPurchaseScaffold(p: p),
    );
  }
}

class _LoadedPurchaseScaffold extends ConsumerWidget {
  const _LoadedPurchaseScaffold({required this.p});

  final TradePurchase p;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this purchase?'),
        content: Text('Remove ${p.humanId}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      invalidatePurchaseWorkspace(ref);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      context.popOrGo('/purchase');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is DioException ? friendlyApiError(e) : 'Could not delete'),
        ),
      );
    }
  }

  Future<void> _runPrintPdf(BuildContext context, WidgetRef ref) async {
    final biz = ref.read(invoiceBusinessProfileProvider);
    await printPurchasePdf(p, biz);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/purchase'),
        ),
        title: Text(p.humanId),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onPressed: p.statusEnum == PurchaseStatus.cancelled
                ? null
                : () => context.push('/purchase/edit/${p.id}'),
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () async {
              final biz = ref.read(invoiceBusinessProfileProvider);
              await sharePurchasePdf(p, biz);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PDF ready to share')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _runPrintPdf(context, ref),
          ),
          if (p.statusEnum != PurchaseStatus.cancelled)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                if (v == 'delete') _confirmDelete(context, ref);
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline,
                          color: Theme.of(ctx).colorScheme.error, size: 22),
                      const SizedBox(width: 12),
                      Text('Delete purchase',
                          style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _PurchaseDetailBody(p: p),
    );
  }
}

class _PurchaseDetailBody extends ConsumerStatefulWidget {
  const _PurchaseDetailBody({required this.p});

  final TradePurchase p;

  @override
  ConsumerState<_PurchaseDetailBody> createState() => _PurchaseDetailBodyState();
}

class _PurchaseDetailBodyState extends ConsumerState<_PurchaseDetailBody> {
  @override
  Widget build(BuildContext context) {
    final p = widget.p;
    final agg = _buildAgg(p);
    final cs = Theme.of(context).colorScheme;
    final st = p.statusEnum;
    final paidPending = st == PurchaseStatus.paid ||
        (p.remaining <= 0.009 && st != PurchaseStatus.cancelled);
    final mismatch = (p.totalAmount - agg.finalComputed).abs() > 0.05;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(_purchaseDetailProvider(p.id));
                await ref.read(_purchaseDetailProvider(p.id).future);
              },
              child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.hasMissingDetails) _pendingDetailsChip(context, p, cs),
                    _compactMeta(context, p, st, paidPending, cs),
                    const SizedBox(height: 18),
                    _summaryHeroCard(context, p, agg, cs),
                    const SizedBox(height: 18),
                    Text(
                      'Items',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                          ),
                    ),
                    const SizedBox(height: 10),
                    ..._itemsAsCards(context, p, cs),
                    const SizedBox(height: 18),
                    _chargesAndBalanceCollapsible(context, p, agg, cs, mismatch),
                  ],
                ),
              ),
            ),
          ),
        ),
        _stickyActionBar(context, ref, p, cs),
      ],
    );
  }

  Widget _pendingDetailsChip(
      BuildContext context, TradePurchase p, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(Icons.edit_note_rounded,
              size: 18, color: Colors.amber.shade900),
          label: Text(
            'Details pending — tap to complete',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade900,
            ),
          ),
          backgroundColor: Colors.amber.shade50,
          side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.35)),
          onPressed: () => context.push('/purchase/edit/${p.id}'),
        ),
      ),
    );
  }

  Widget _compactMeta(
    BuildContext context,
    TradePurchase p,
    PurchaseStatus st,
    bool paidPending,
    ColorScheme cs,
  ) {
    final sup = (p.supplierName ?? '—').trim();
    final bro = (p.brokerName ?? '—').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                sup.isEmpty ? '—' : sup,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: st.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                paidPending ? 'Paid' : st.label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: st.color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Broker: ${bro.isEmpty ? '—' : bro}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          DateFormat('d MMM yyyy').format(p.purchaseDate),
          style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
        ),
        if (p.paymentDays != null)
          Text(
            'Payment: ${p.paymentDays} days',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        if (p.invoiceNumber != null && p.invoiceNumber!.trim().isNotEmpty)
          Text(
            'Ref: ${p.invoiceNumber!.trim()}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _summaryHeroCard(
      BuildContext context, TradePurchase p, _Agg agg, ColorScheme cs) {
    final profitColor =
        agg.sumProfit >= 0 ? const Color(0xFF0F766E) : HexaColors.loss;
    final volParts = <String>[];
    if (agg.totalKg > 1e-6) volParts.add('${_qtyFmt(agg.totalKg)} kg');
    if (agg.totalBags > 1e-6) {
      volParts.add(
          '${_qtyFmt(agg.totalBags)} ${agg.totalBags == 1 ? 'bag' : 'bags'}');
    }
    if (agg.totalBox > 1e-6) {
      volParts.add(
          '${_qtyFmt(agg.totalBox)} ${agg.totalBox == 1 ? 'box' : 'boxes'}');
    }
    if (agg.totalTin > 1e-6) {
      volParts.add(
          '${_qtyFmt(agg.totalTin)} ${agg.totalTin == 1 ? 'tin' : 'tins'}');
    }
    final hasSell = agg.sumSellingGross > 1e-6;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outline.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Total (this bill)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            _inr(agg.finalComputed, fractionDigits: 0),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
              height: 1.05,
            ),
          ),
          if (volParts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              volParts.join(' · '),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: cs.primary,
              ),
            ),
          ],
          if (hasSell) ...[
            const SizedBox(height: 8),
            Text(
              'Est. sell value ${_inr(agg.sumSellingGross, fractionDigits: 0)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
          if (agg.sumProfit.abs() > 1e-6 || hasSell) ...[
            const SizedBox(height: 8),
            Text(
              'Profit ${_inr(agg.sumProfit, fractionDigits: 0)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: profitColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _chargesAndBalanceCollapsible(
    BuildContext context,
    TradePurchase p,
    _Agg agg,
    ColorScheme cs,
    bool mismatch,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        initiallyExpanded: false,
        title: Text(
          'Charges & balance',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        subtitle: Text(
          'Freight, commission, payment',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
        children: [
          _miniCharges(context, agg, cs),
          const SizedBox(height: 8),
          _balanceRows(context, p, cs),
          if (mismatch)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text(
                'Stored total ${_inr(p.totalAmount)} differs from calculated '
                '${_inr(agg.finalComputed)} by ${_inr((p.totalAmount - agg.finalComputed).abs())}.',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.error,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _balanceRows(BuildContext context, TradePurchase p, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Remaining',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              SelectableText(
                _inr(p.remaining),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          if (p.dueDate != null) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Due',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
                Text(
                  DateFormat.yMMMd().format(p.dueDate!),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  ({String purchase, String selling}) _lineRateLabels(TradePurchaseLine l) {
    final u = l.unit.trim();
    final ul = u.toLowerCase();
    final pk = tradePurchaseLineDisplayPurchaseRate(l);
    final sk = tradePurchaseLineDisplaySellingRate(l);
    final pSuffix =
        (tradePurchaseLineIsWeightPriced(l) || ul == 'kg') ? '/kg' : '/$u';
    final purchase = '${_inr(pk)}$pSuffix';
    if (sk != null) {
      final sSuffix =
          (tradePurchaseLineIsWeightPriced(l) || ul == 'kg') ? '/kg' : '/$u';
      return (purchase: purchase, selling: '${_inr(sk)}$sSuffix');
    }
    if (l.kgPerUnit != null &&
        l.landingCostPerKg != null &&
        l.kgPerUnit! > 0 &&
        l.landingCostPerKg! > 0) {
      final kgQty = l.qty * l.kgPerUnit!;
      if (kgQty > 1e-9) {
        final implied = l.sellingGross / kgQty;
        return (purchase: purchase, selling: '${_inr(implied)}/kg');
      }
    }
    return (purchase: purchase, selling: '—');
  }

  String _lineQtyHuman(TradePurchaseLine l) {
    final q = _qtyFmt(l.qty);
    final u = l.unit.trim();
    final kg = _lineKg(l);
    final ul = u.toLowerCase();
    if (kg > 1e-6 &&
        (ul == 'bag' ||
            ul == 'sack' ||
            ul == 'box' ||
            ul == 'tin' ||
            ul == 'kg')) {
      return '$q $u · ${_qtyFmt(kg)} kg';
    }
    return '$q $u';
  }

  List<Widget> _itemsAsCards(
      BuildContext context, TradePurchase p, ColorScheme cs) {
    final out = <Widget>[];
    var i = 0;
    for (final l in p.lines) {
      i++;
      final pr = _effectiveLineProfit(l);
      final rates = _lineRateLabels(l);
      final profitColor =
          pr == null ? cs.onSurfaceVariant : (pr >= 0 ? const Color(0xFF0F766E) : HexaColors.loss);
      out.add(
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$i.',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      message: _unitClassificationHint(l),
                      child: Text(
                        l.itemName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _lineQtyHuman(l),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'P: ${rates.purchase}  ·  S: ${rates.selling}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Line total',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  SelectableText(
                    _inr(_lineInclusive(l)),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                  ),
                ],
              ),
              if (pr != null) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Profit',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    SelectableText(
                      _inr(pr),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: profitColor,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }
    return out;
  }

  Widget _miniCharges(BuildContext context, _Agg agg, ColorScheme cs) {
    Widget tiny(String k, String v) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              k,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
            ),
            SelectableText(
              v,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final rows = <Widget>[];
    if (agg.headerDiscountPct > 1e-6) {
      rows.add(tiny(
        'Purchase discount',
        '${agg.headerDiscountPct.toStringAsFixed(1)}% (−${_inr(agg.discountRupeeEffect)})',
      ));
    }
    rows.add(tiny(
      'Freight',
      agg.freightIncluded ? 'Included' : (agg.freight > 1e-6 ? _inr(agg.freight) : '—'),
    ));
    rows.add(tiny('Commission', agg.commission > 1e-6 ? _inr(agg.commission) : '—'));
    rows.add(tiny('Billty', agg.billty > 1e-6 ? _inr(agg.billty) : '—'));
    rows.add(tiny('Delivered', agg.delivered > 1e-6 ? _inr(agg.delivered) : '—'));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }

  Widget _stickyActionBar(
    BuildContext context,
    WidgetRef ref,
    TradePurchase p,
    ColorScheme cs,
  ) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    Widget cell(Widget child) => Expanded(child: child);

    Future<void> download() async {
      final biz = ref.read(invoiceBusinessProfileProvider);
      try {
        await downloadPurchasePdf(p, biz);
        if (context.mounted) {
          if (kIsWeb) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Use the browser print/save dialog to download PDF',
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Use Save as PDF or share from the dialog to save the file',
                ),
              ),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is DioException
                    ? friendlyApiError(e)
                    : 'Something went wrong. Please try again.',
              ),
            ),
          );
        }
      }
    }

    return Material(
      elevation: 10,
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                cell(
                  OutlinedButton(
                    onPressed: p.statusEnum == PurchaseStatus.paid ||
                            p.statusEnum == PurchaseStatus.cancelled
                        ? null
                        : () => _markPaidSheet(context, ref, p),
                    child: const Text('Mark paid'),
                  ),
                ),
                const SizedBox(width: 10),
                cell(
                  OutlinedButton(
                    onPressed: () async {
                      final biz = ref.read(invoiceBusinessProfileProvider);
                      await sharePurchasePdf(p, biz);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('PDF ready to share')),
                        );
                      }
                    },
                    child: const Text('Share'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                cell(
                  OutlinedButton(
                    onPressed: p.statusEnum == PurchaseStatus.cancelled
                        ? null
                        : () => context.push('/purchase/edit/${p.id}'),
                    child: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                cell(
                  OutlinedButton(
                    onPressed: download,
                    child: const Text('Download'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markPaidSheet(BuildContext context, WidgetRef ref, TradePurchase p) async {
    final ctrl = TextEditingController(text: p.remaining.toStringAsFixed(2));
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Record payment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount paid (total on purchase)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final v = double.tryParse(ctrl.text.trim());
    if (v == null || v < 0) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).patchPurchasePayment(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            paidAmount: v,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(_purchaseDetailProvider(p.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment saved')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is DioException
                  ? friendlyApiError(e)
                  : 'Something went wrong. Please try again.',
            ),
          ),
        );
      }
    }
  }
}
