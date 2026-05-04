import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
            tooltip: 'Delete',
            icon: Icon(
              Icons.delete_outline,
              color: p.statusEnum == PurchaseStatus.cancelled
                  ? null
                  : Theme.of(context).colorScheme.error,
            ),
            onPressed:
                p.statusEnum == PurchaseStatus.cancelled ? null : () => _confirmDelete(context, ref),
          ),
          IconButton(
            tooltip: 'Print PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _runPrintPdf(context, ref),
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

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_purchaseDetailProvider(p.id));
          await ref.read(_purchaseDetailProvider(p.id).future);
        },
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
          children: [
            if (p.hasMissingDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  child: ListTile(
                    leading: Icon(Icons.warning_amber_rounded,
                        color: Colors.orange.shade900),
                    title: const Text('Complete details pending'),
                    subtitle: const Text(
                        'Broker, payment days, freight, or discount can still be filled in.'),
                    trailing: TextButton(
                      onPressed: () => context.push('/purchase/edit/${p.id}'),
                      child: const Text('Edit'),
                    ),
                  ),
                ),
              ),
            _headerBlock(context, p, st, paidPending),
            Divider(height: 24, thickness: 1, color: cs.outline.withValues(alpha: 0.25)),
            _summarySection(context, p, agg, cs),
            Divider(height: 24, thickness: 1, color: cs.outline.withValues(alpha: 0.25)),
            Text(
              'Items',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 0.4),
            ),
            const SizedBox(height: 6),
            _itemsTableArea(context, p, agg),
            Divider(height: 24, thickness: 1, color: cs.outline.withValues(alpha: 0.25)),
            Text(
              'Cost breakdown',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: 0.4),
            ),
            const SizedBox(height: 8),
            _costRows(context, p, agg),
            const SizedBox(height: 14),
            _secondaryActions(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _headerBlock(
    BuildContext context,
    TradePurchase p,
    PurchaseStatus st,
    bool paidPending,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Supplier',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                  ),
                  SelectableText(
                    (p.supplierName ?? '—').trim().isEmpty ? '—' : p.supplierName!.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Broker',
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
                  ),
                  SelectableText(
                    (p.brokerName ?? '—').trim().isEmpty ? '—' : p.brokerName!.trim(),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: st.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    paidPending ? 'Paid' : 'Pending',
                    style: TextStyle(
                        fontWeight: FontWeight.w900, color: cs.primary, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    st.label,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: st.color),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _pairRow(context, 'Date', DateFormat.yMMMd().add_jm().format(p.purchaseDate)),
        _pairRow(
          context,
          'Payment terms',
          p.paymentDays != null ? '${p.paymentDays} days' : '—',
        ),
        if (p.invoiceNumber != null && p.invoiceNumber!.trim().isNotEmpty)
          _pairRow(context, 'Invoice', p.invoiceNumber!.trim()),
      ],
    );
  }

  Widget _pairRow(BuildContext context, String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  Widget _summarySection(BuildContext context, TradePurchase p, _Agg agg, ColorScheme cs) {
    final profitColor = agg.sumProfit >= 0 ? const Color(0xFF0F766E) : HexaColors.loss;
    final mismatch = (p.totalAmount - agg.finalComputed).abs() > 0.05;

    Widget moneyLine(String title, num value, [Color? c, FontWeight w = FontWeight.w800]) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            SelectableText(
              _inr(value),
              style: TextStyle(fontWeight: w, fontSize: 16, color: c ?? cs.onSurface),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        moneyLine('Total Purchase (computed)', agg.finalComputed, cs.onSurface),
        SelectableText(
          'Landing subtotal ${_inr(agg.sumLandingGross)} · Lines (incl. tax/disc) ${_inr(agg.linesInclusive)}',
          style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
        ),
        if (mismatch)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: SelectableText(
              'Stored bill total ${_inr(p.totalAmount)} — differs from engine by '
              '${_inr((p.totalAmount - agg.finalComputed).abs())}. '
              'Breakdown FINAL TOTAL follows engine.',
              style: TextStyle(fontSize: 11, color: cs.error, height: 1.35),
            ),
          ),
        const Divider(height: 16),
        moneyLine('Total Selling', agg.sumSellingGross, null, FontWeight.w800),
        moneyLine('Profit', agg.sumProfit, profitColor, FontWeight.w900),
        const Divider(height: 18),
        _metricRow(context, 'Total Weight', '${_qtyFmt(agg.totalKg)} kg'),
        _metricRow(context, 'Total Bags', _qtyFmt(agg.totalBags)),
        _metricRow(context, 'Total Box', _qtyFmt(agg.totalBox)),
        _metricRow(context, 'Total Tin', _qtyFmt(agg.totalTin)),
      ],
    );
  }

  Widget _metricRow(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            k,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          SelectableText(
            v,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _itemsTableArea(BuildContext context, TradePurchase p, _Agg agg) {
    return LayoutBuilder(
      builder: (context, lc) {
        final minTabW = lc.maxWidth < 600 ? 900.0 : lc.maxWidth;

        Widget numCell(num v, [FontWeight w = FontWeight.w700]) {
          return Align(
            alignment: Alignment.centerRight,
            child: SelectableText(
              _inr(v),
              style: TextStyle(fontWeight: w, fontSize: 12.8),
              textAlign: TextAlign.right,
            ),
          );
        }

        final headerStyle = Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.w900);

        Widget hLeft(String label) => Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
              child: Text(
                label,
                style: headerStyle?.copyWith(letterSpacing: 0.2),
              ),
            );

        Widget hRight(String label) => Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  label,
                  style: headerStyle?.copyWith(letterSpacing: 0.2),
                  textAlign: TextAlign.right,
                ),
              ),
            );

        final rows = <TableRow>[
          TableRow(
            children: [
              hLeft('Item'),
              hRight('Qty'),
              hLeft('Unit'),
              hRight('Kg'),
              hRight('Landing'),
              hRight('Selling'),
              hRight('Profit'),
              hRight('Total'),
            ],
          ),
        ];

        for (final l in p.lines) {
          final pr = _effectiveLineProfit(l);
          rows.add(
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Tooltip(
                    message: _unitClassificationHint(l),
                    child: SelectableText(
                      l.itemName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13, height: 1.25),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: SelectableText(
                      _qtyFmt(l.qty),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: SelectableText(
                    l.unit,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SelectableText(
                      _qtyFmt(_lineKg(l)),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: numCell(l.landingGross, FontWeight.w800)),
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: numCell(l.sellingGross, FontWeight.w800)),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: SelectableText(
                      pr == null ? '—' : _inr(pr),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.8,
                        color: pr == null
                            ? null
                            : (pr >= 0 ? Colors.teal.shade800 : HexaColors.loss),
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ),
                Padding(
                    padding: const EdgeInsets.all(8),
                    child: numCell(_lineInclusive(l), FontWeight.w900)),
              ],
            ),
          );
        }

        rows.add(const TableRow(children: [
          SizedBox(height: 6),
          SizedBox.shrink(),
          SizedBox.shrink(),
          SizedBox.shrink(),
          SizedBox.shrink(),
          SizedBox.shrink(),
          SizedBox.shrink(),
          SizedBox.shrink(),
        ]));

        rows.add(TableRow(
          decoration: BoxDecoration(
            color:
                Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Totals',
                style:
                    Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox.shrink(),
            const SizedBox.shrink(),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _qtyFmt(agg.totalKg),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(12), child: numCell(agg.sumLandingGross)),
            Padding(padding: const EdgeInsets.all(12), child: numCell(agg.sumSellingGross)),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerRight,
                child: SelectableText(
                  _inr(agg.sumProfit),
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color:
                          agg.sumProfit >= 0 ? Colors.teal.shade900 : HexaColors.loss),
                  textAlign: TextAlign.right,
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.all(12), child: numCell(agg.linesInclusive)),
          ],
        ));

        return Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            primary: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minTabW),
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1),
                  4: FlexColumnWidth(1.35),
                  5: FlexColumnWidth(1.35),
                  6: FlexColumnWidth(1.35),
                  7: FlexColumnWidth(1.35),
                },
                border: TableBorder(
                  horizontalInside: BorderSide(
                    width: 0.5,
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  ),
                  verticalInside: BorderSide(
                    width: 0.5,
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
                  ),
                ),
                children: rows,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _costRows(BuildContext context, TradePurchase p, _Agg agg) {
    Widget row(String k, String v) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                k,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: SelectableText(
                v,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      );
    }

    final disc = agg.headerDiscountPct <= 0
        ? '—'
        : '${agg.headerDiscountPct.toStringAsFixed(2)}% (−${_inr(agg.discountRupeeEffect)})';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row('Lines (incl. tax / line disc)', _inr(agg.linesInclusive)),
        row('Header discount', disc),
        row(
          'Freight',
          agg.freightIncluded
              ? 'Included in rate'
              : (agg.freight > 0 ? _inr(agg.freight) : '—'),
        ),
        row('Commission', agg.commission > 0 ? _inr(agg.commission) : '—'),
        row('Billty', agg.billty > 0 ? _inr(agg.billty) : '—'),
        row('Delivered', agg.delivered > 0 ? _inr(agg.delivered) : '—'),
        const Divider(height: 20),
        row('FINAL TOTAL', _inr(agg.finalComputed)),
        row('Stored bill total', _inr(p.totalAmount)),
        const SizedBox(height: 8),
        row('Paid', _inr(p.paidAmount)),
        row('Remaining', _inr(p.remaining)),
        if (p.dueDate != null) row('Due date', DateFormat.yMMMd().format(p.dueDate!)),
      ],
    );
  }

  Widget _secondaryActions(BuildContext context, WidgetRef ref) {
    final p = widget.p;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: p.statusEnum == PurchaseStatus.paid ||
                  p.statusEnum == PurchaseStatus.cancelled
              ? null
              : () => _markPaidSheet(context, ref, p),
          icon: const Icon(Icons.payments_rounded, size: 18),
          label: const Text('Mark paid'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final biz = ref.read(invoiceBusinessProfileProvider);
            await sharePurchasePdf(p, biz);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PDF ready to share')),
              );
            }
          },
          icon: const Icon(Icons.share_outlined, size: 18),
          label: const Text('Share PDF'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final biz = ref.read(invoiceBusinessProfileProvider);
            try {
              await downloadPurchasePdf(p, biz);
              if (context.mounted) {
                if (kIsWeb) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Use the browser print/save dialog to download PDF'),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Use Save as PDF or share from the dialog to save the file'),
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
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download'),
        ),
        OutlinedButton.icon(
          onPressed: () => _whatsappPurchasePdf(context, ref, p),
          icon: const Icon(Icons.chat_rounded, size: 18),
          label: const Text('WhatsApp'),
        ),
      ],
    );
  }

  String? _waPhoneDigits(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    if (d.length < 10) return null;
    if (d.length == 10) return '91$d';
    return d;
  }

  Future<void> _whatsappPurchasePdf(
      BuildContext context, WidgetRef ref, TradePurchase p) async {
    final biz = ref.read(invoiceBusinessProfileProvider);
    await sharePurchasePdf(p, biz);
    if (!context.mounted) return;
    final digits = _waPhoneDigits(p.supplierWhatsapp ?? p.supplierPhone);
    if (digits == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'PDF shared. Add supplier WhatsApp or phone to open a chat.'),
        ),
      );
      return;
    }
    final msg = Uri.encodeComponent(
      '${p.humanId} — Total ${_inr(p.totalAmount)}, Remaining ${_inr(p.remaining)}. (Attach the PDF from the share sheet.)',
    );
    final u = Uri.parse('https://wa.me/$digits?text=$msg');
    if (await canLaunchUrl(u)) {
      await launchUrl(u, mode: LaunchMode.externalApplication);
    }
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
