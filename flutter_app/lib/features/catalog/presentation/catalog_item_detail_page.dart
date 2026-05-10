import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/models/trade_purchase_models.dart' show TradePurchaseLine;
import '../../../core/router/navigation_ext.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/catalog/item_trade_history.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';
import '../../../shared/widgets/trade_intel_cards.dart';
import '../../../shared/widgets/search_picker_sheet.dart';

class CatalogItemDetailPage extends ConsumerStatefulWidget {
  const CatalogItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<CatalogItemDetailPage> createState() =>
      _CatalogItemDetailPageState();
}

class _CatalogItemDetailPageState extends ConsumerState<CatalogItemDetailPage> {
  int _historyRangeDays = kDefaultItemHistoryRangeDays;
  static const int _kMaxHistoryRows = 200;
  final _histSearchCtrl = TextEditingController();

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 0,
    ).format(n);
  }

  Future<void> _editItemDefaults(Map<String, dynamic> item) async {
    var unit = item['default_unit']?.toString();
    final nameCtrl =
        TextEditingController(text: item['name']?.toString() ?? '');
    final hsnCtrl =
        TextEditingController(text: item['hsn_code']?.toString() ?? '');
    final taxCtrl = TextEditingController(
        text: item['tax_percent'] != null ? item['tax_percent'].toString() : '');
    final kgCtrl = TextEditingController(
      text: item['default_kg_per_bag'] != null
          ? item['default_kg_per_bag'].toString()
          : '',
    );
    final ipbCtrl = TextEditingController(
      text: item['default_items_per_box'] != null
          ? item['default_items_per_box'].toString()
          : '',
    );
    final wptCtrl = TextEditingController(
      text: item['default_weight_per_tin'] != null
          ? item['default_weight_per_tin'].toString()
          : '',
    );
    final landCtrl = TextEditingController(
      text: item['default_landing_cost'] != null
          ? item['default_landing_cost'].toString()
          : '',
    );
    final sellCtrl = TextEditingController(
      text: item['default_selling_cost'] != null
          ? item['default_selling_cost'].toString()
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Edit item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: hsnCtrl,
                  decoration: const InputDecoration(labelText: 'HSN code'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: taxCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tax %',
                    hintText: 'e.g. 5',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Default unit (optional)',
                  style: Theme.of(ctx)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () async {
                    const none = '__unit_none__';
                    final id = await showSearchPickerSheet<String>(
                      context: ctx,
                      title: 'Default unit',
                      rows: const [
                        SearchPickerRow(value: none, title: '— (unspecified)'),
                        SearchPickerRow(value: 'kg', title: 'kg'),
                        SearchPickerRow(value: 'bag', title: 'bag'),
                        SearchPickerRow(value: 'box', title: 'box'),
                        SearchPickerRow(value: 'piece', title: 'piece'),
                      ],
                      selectedValue: unit ?? none,
                    );
                    if (!ctx.mounted) return;
                    if (id != null) setSt(() => unit = id == none ? null : id);
                  },
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(unit == null ? '— (unspecified)' : '$unit'),
                  ),
                ),
                if (unit == 'bag') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: kgCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Default kg per bag (optional)',
                      hintText: 'e.g. 50',
                    ),
                    onChanged: (_) => setSt(() {}),
                  ),
                  const SizedBox(height: 8),
                  BagDefaultUnitHint(
                    kgAlreadySet: () {
                      final v = parseOptionalKgPerBag(kgCtrl.text);
                      return v != null && v > 0;
                    }(),
                  ),
                ],
                if (unit == 'box') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: ipbCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Items per box',
                      hintText: 'How many pieces per box',
                    ),
                  ),
                ],
                if (unit == 'tin') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: wptCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Liters / weight per tin',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: landCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Default landing (₹)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: sellCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Default selling (₹)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => ctx.pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => ctx.pop(true),
                child: const Text('Save')),
          ],
        ),
      ),
    );
    try {
      if (ok != true) return;
      final session = ref.read(sessionProvider);
      if (session == null) return;
      final kgParsed =
          unit == 'bag' ? parseOptionalKgPerBag(kgCtrl.text) : null;
      final tax = double.tryParse(taxCtrl.text.trim());
      final ipb = double.tryParse(ipbCtrl.text.trim());
      final wpt = double.tryParse(wptCtrl.text.trim());
      final land = double.tryParse(landCtrl.text.trim());
      final sell = double.tryParse(sellCtrl.text.trim());
      await ref.read(hexaApiProvider).updateCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            name: nameCtrl.text.trim().isEmpty
                ? null
                : nameCtrl.text.trim(),
            hsnCode: hsnCtrl.text.trim().isEmpty ? null : hsnCtrl.text.trim(),
            taxPercent: tax,
            defaultLandingCost: land,
            defaultSellingCost: sell,
            includeDefaultUnit: true,
            defaultUnit: unit,
            patchDefaultKgPerBag: unit == 'bag',
            defaultKgPerBag: kgParsed,
            patchDefaultItemsPerBox: unit == 'box',
            defaultItemsPerBox: ipb,
            patchDefaultWeightPerTin: unit == 'tin',
            defaultWeightPerTin: wpt,
          );
      ref.invalidate(catalogItemDetailProvider(widget.itemId));
      ref.invalidate(tradePurchasesCatalogIntelProvider);
      invalidatePurchaseWorkspace(ref);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    } finally {
      nameCtrl.dispose();
      hsnCtrl.dispose();
      taxCtrl.dispose();
      kgCtrl.dispose();
      ipbCtrl.dispose();
      wptCtrl.dispose();
      landCtrl.dispose();
      sellCtrl.dispose();
    }
  }

  @override
  void dispose() {
    _histSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(catalogItemDetailProvider(widget.itemId));
    ref.invalidate(tradePurchasesCatalogIntelProvider);
    await ref.read(catalogItemDetailProvider(widget.itemId).future);
  }

  String _pdfMoney(num? n) {
    if (n == null) return '-';
    return _inr(n).replaceAll('₹', 'Rs. ');
  }

  String _pdfLandingCol(TradePurchaseLine ln) {
    final kpu = ln.kgPerUnit;
    final lcpk = ln.landingCostPerKg;
    if (kpu != null && lcpk != null && kpu > 0 && lcpk > 0) {
      return 'Rs. ${_fmtNum(lcpk)}/kg';
    }
    return 'Rs. ${_fmtNum(ln.landingCost)}/${ln.unit}';
  }

  Future<void> _exportItemPdf(
    String itemName,
    List<ItemTradeHistoryRow> hist,
  ) async {
    if (hist.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No trade lines to export.')),
        );
      }
      return;
    }
    try {
      final biz = ref.read(invoiceBusinessProfileProvider);
      final df = DateFormat('dd MMM yyyy');
      final rows = <List<String>>[];
      var sum = 0.0;
      for (final r in hist) {
        final ln = r.line;
        sum += r.lineTotal;
        final broker = (r.brokerName ?? '').trim();
        rows.add([
          df.format(r.purchaseDate),
          r.supplierName,
          broker.isEmpty ? '-' : broker,
          '${_fmtNum(ln.qty)} ${ln.unit}',
          r.rateLabel().replaceAll('₹', 'Rs. '),
          _pdfLandingCol(ln),
          _pdfMoney(ln.sellingCost),
          _pdfMoney(r.lineTotal),
        ]);
      }
      final now = DateTime.now();
      final periodTo = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final periodFrom = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: _historyRangeDays));
      final totalLabel =
          'Total: Rs. ${NumberFormat('#,##,##0', 'en_IN').format(sum.round())} '
          '(${hist.length} lines)';
      await shareItemPurchaseTradeHistoryPdf(
        business: biz,
        itemName: itemName,
        rows: rows,
        periodFrom: periodFrom,
        periodTo: periodTo,
        periodDescription: 'Last $_historyRangeDays days (trade)',
        totalLineLabel: totalLabel,
      );
    } catch (e) {
      if (mounted) {
        final msg = e is DioException
            ? friendlyApiError(e)
            : 'Could not create PDF. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF failed. $msg')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _histSearchCtrl.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(businessDataWriteRevisionProvider, (prev, next) {
      if (prev != null && next > prev) {
        ref.invalidate(catalogItemDetailProvider(widget.itemId));
        ref.invalidate(catalogItemTradeSupplierPricesProvider(widget.itemId));
        ref.invalidate(tradePurchasesCatalogIntelProvider);
      }
    });

    final itemAsync = ref.watch(catalogItemDetailProvider(widget.itemId));
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final purchasesAsync =
        ref.watch(tradePurchasesCatalogIntelParsedProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/catalog'),
        ),
        title: itemAsync.when(
          data: (m) => Text(
            m['name']?.toString() ?? 'Item',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          loading: () => const Text('Item'),
          error: (_, __) => const Text('Catalog item'),
        ),
        actions: [
          IconButton(
            tooltip: 'Item ledger & statement',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () =>
                context.push('/catalog/item/${widget.itemId}/ledger'),
          ),
          IconButton(
            tooltip: 'Purchase history',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push(
              '/catalog/item/${widget.itemId}/purchase-history',
            ),
          ),
        ],
      ),
      body: itemAsync.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const DetailSkeleton(),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load catalog item',
          onRetry: () =>
              ref.invalidate(catalogItemDetailProvider(widget.itemId)),
        ),
        data: (item) {
          String? catName;
          if (catsAsync.hasValue) {
            final cid = item['category_id']?.toString();
            for (final c in catsAsync.value!) {
              if (c['id']?.toString() == cid) {
                catName = c['name']?.toString();
                break;
              }
            }
          }
          final hsn = item['hsn_code']?.toString();

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Text(
                  item['name']?.toString() ?? 'Item',
                  style: HexaDsType.catalogItemHeroName,
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: catName == null || catName.isEmpty
                      ? null
                      : () {
                          final c = catName!;
                          context.push(
                            '/contacts/category?name=${Uri.encodeComponent(c)}',
                          );
                        },
                  child: Text(
                    [
                      if (catName != null && catName.isNotEmpty) catName,
                      item['type_name']?.toString(),
                    ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                // Enrich hero card with last-line qty/unit/kg from loaded purchases
                // so "Last" shows bags/kg, not just rate.
                Builder(builder: (ctx) {
                  final pv = purchasesAsync.value;
                  Map<String, dynamic> hero = Map<String, dynamic>.from(item);
                  if (pv != null && pv.isNotEmpty) {
                    TradePurchaseLine? last;
                    DateTime? lastAt;
                    for (final p in pv) {
                      for (final ln in p.lines) {
                        if ((ln.catalogItemId ?? '') != widget.itemId) continue;
                        if (lastAt == null || p.purchaseDate.isAfter(lastAt)) {
                          lastAt = p.purchaseDate;
                          last = ln;
                        }
                      }
                    }
                    if (last != null) {
                      final ln = last;
                      hero['last_line_qty'] = ln.qty;
                      hero['last_line_unit'] = ln.unit;
                      final tw = ln.totalWeight;
                      final wk = (tw != null && tw > 0)
                          ? tw
                          : (ln.kgPerUnit != null && ln.kgPerUnit! > 0)
                              ? (ln.qty * ln.kgPerUnit!)
                              : null;
                      hero['last_line_weight_kg'] = wk;
                      hero['kg_per_unit'] = ln.kgPerUnit ?? ln.defaultKgPerBag;
                      if (ln.landingCostPerKg != null && ln.landingCostPerKg! > 0) {
                        hero['last_purchase_price'] = ln.landingCostPerKg;
                        hero['purchase_rate_dim'] = 'kg';
                      } else {
                        hero['last_purchase_price'] = ln.purchaseRate ?? ln.landingCost;
                        hero['purchase_rate_dim'] =
                            ln.unit.trim().isEmpty ? null : ln.unit.trim().toLowerCase();
                      }
                      if (ln.sellingRate != null && ln.sellingRate! > 0) {
                        hero['last_selling_rate'] = ln.sellingRate;
                        hero['selling_rate_dim'] = hero['purchase_rate_dim'];
                      }
                    }
                  }
                  return _ItemTradeHeroCard(item: hero);
                }),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => context.push(
                    '/purchase/new?catalogItemId=${Uri.encodeComponent(widget.itemId)}',
                  ),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('New purchase'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF17A8A7),
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                if (hsn != null && hsn.isNotEmpty) ...[
                  Text(
                    'HSN $hsn',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
                _CatalogItemDefaultParties(item: item, ref: ref),
                const SizedBox(height: 12),
                purchasesAsync.when(
                  skipLoadingOnReload: true,
                  skipLoadingOnRefresh: true,
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => FriendlyLoadError(
                    message: 'Could not load purchase history',
                    onRetry: () =>
                        ref.invalidate(tradePurchasesCatalogIntelProvider),
                  ),
                  data: (purchases) {
                    final itemName = item['name']?.toString() ?? 'Item';
                    final hist = itemTradeHistoryRows(
                      purchases,
                      widget.itemId,
                      catalogItemName: itemName,
                    );
                    final rangeHist =
                        itemTradeHistoryRowsInRange(hist, _historyRangeDays);
                    final baseRecent =
                        rangeHist.take(_kMaxHistoryRows).toList();
                    final q = _histSearchCtrl.text.trim().toLowerCase();
                    final recent = q.isEmpty
                        ? baseRecent
                        : baseRecent.where((r) {
                            if (r.humanId.toLowerCase().contains(q)) {
                              return true;
                            }
                            if (r.supplierName.toLowerCase().contains(q)) {
                              return true;
                            }
                            if (r.line.itemName.toLowerCase().contains(q)) {
                              return true;
                            }
                            return DateFormat('dd MMM yyyy')
                                .format(r.purchaseDate)
                                .toLowerCase()
                                .contains(q);
                          }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (hist.isEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            'No purchases recorded for this item yet',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        _ItemSectionLabel(
                          label:
                              'Recent history · last $_historyRangeDays days (trade)',
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _histSearchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search invoice, supplier, item…',
                            filled: true,
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            prefixIcon: const Icon(Icons.search, size: 20),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ChoiceChip(
                              label: const Text('30d'),
                              selected: _historyRangeDays == 30,
                              onSelected: (_) => setState(
                                () => _historyRangeDays = 30,
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('90d'),
                              selected: _historyRangeDays == 90,
                              onSelected: (_) => setState(
                                () => _historyRangeDays = 90,
                              ),
                            ),
                            ChoiceChip(
                              label: const Text('365d'),
                              selected: _historyRangeDays == 365,
                              onSelected: (_) => setState(
                                () => _historyRangeDays = 365,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (recent.isEmpty)
                          Text(
                            hist.isEmpty
                                ? 'No lines in latest 200 purchases.'
                                : 'No purchases in this date range.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          )
                        else
                          _TradeHistoryLedgerTable(
                            rows: recent,
                            cs: Theme.of(context).colorScheme,
                            fmtDate: _fmtDate,
                            fmtNum: _fmtNum,
                            inr: _inr,
                          ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              context.push('/catalog/item/${widget.itemId}/ledger'),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('View full statement & ledger'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _exportItemPdf(itemName, rangeHist),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Download PDF statement'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),

                // ── DEFAULTS ──────────────────────────────────────────────
                const _ItemSectionLabel(label: 'Defaults'),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final du = item['default_unit']?.toString();
                            final dkg = item['default_kg_per_bag'];
                            final line = (du == null || du.isEmpty)
                                ? 'No default unit'
                                : (du == 'bag' && dkg != null)
                                    ? 'Default: $du · $dkg kg/bag'
                                    : 'Default unit: $du';
                            return Text(
                              line,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                            );
                          },
                        ),
                      ),
                      TextButton(
                        onPressed: () => _editItemDefaults(item),
                        child: const Text('Edit'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

}


String _fmtDate(String raw) {
  final d = DateTime.tryParse(raw);
  if (d == null) return raw.split('T').first;
  return DateFormat('d MMM').format(d);
}

String _fmtNum(double n) =>
    n == n.roundToDouble() ? n.toInt().toString() : n.toStringAsFixed(2);

class _ItemSectionLabel extends StatelessWidget {
  const _ItemSectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: HexaDsType.formSectionLabel,
    );
  }
}

class _TradeHistoryLedgerTable extends StatelessWidget {
  const _TradeHistoryLedgerTable({
    required this.rows,
    required this.cs,
    required this.fmtDate,
    required this.fmtNum,
    required this.inr,
  });

  final List<ItemTradeHistoryRow> rows;
  final ColorScheme cs;
  final String Function(String raw) fmtDate;
  final String Function(double n) fmtNum;
  final String Function(num? n) inr;

  @override
  Widget build(BuildContext context) {
    final border = TableBorder.symmetric(
      inside: BorderSide(
        color: cs.outlineVariant.withValues(alpha: 0.4),
        width: 0.5,
      ),
    );
    TextStyle h() => HexaDsType.label(12, color: cs.onSurfaceVariant);
    return LayoutBuilder(
      builder: (context, c) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Material(
            color: cs.surfaceContainerLowest.withValues(alpha: 0.35),
            child: Scrollbar(
              thumbVisibility: false,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: math.max(c.maxWidth, 320),
                  ),
                  child: Table(
                    border: border,
                    columnWidths: const {
                      0: FixedColumnWidth(56),
                      1: FlexColumnWidth(2.0),
                      2: FlexColumnWidth(1.1),
                      3: FixedColumnWidth(80),
                      4: FixedColumnWidth(80),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    children: [
                      TableRow(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        ),
                        children: [
                          _thCell('Date', h(), padEnd: 4),
                          _thCell('Supplier', h()),
                          _thCell('Qty', h()),
                          _thCell('Rate', h(), align: TextAlign.end, padStart: 4),
                          _thCell('Total', h(), align: TextAlign.end, padStart: 4),
                        ],
                      ),
                      for (final r in rows)
                        TableRow(
                          children: [
                            _tdCell(
                              Text(
                                fmtDate(r.purchaseDate.toIso8601String()),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            _tdCell(
                              Text(
                                r.supplierName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HexaDsType.purchaseQtyUnit.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            _tdCell(
                              Text(
                                '${fmtNum(r.line.qty)} ${r.line.unit}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: HexaDsType.purchaseQtyUnit
                                    .copyWith(fontSize: 12),
                              ),
                            ),
                            _tdCell(
                              Text(
                                r.rateLabel(),
                                textAlign: TextAlign.end,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            _tdCell(
                              Text(
                                inr(r.lineTotal),
                                textAlign: TextAlign.end,
                                style: HexaDsType.purchaseLineMoney
                                    .copyWith(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static Widget _thCell(
    String t,
    TextStyle style, {
    TextAlign align = TextAlign.start,
    double padStart = 6,
    double padEnd = 6,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(padStart, 8, padEnd, 8),
      child: Text(t, textAlign: align, style: style),
    );
  }

  static Widget _tdCell(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: child,
    );
  }
}

class _ItemTradeHeroCard extends StatelessWidget {
  const _ItemTradeHeroCard({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final qty = tradeIntelQtySummaryLine(item);
    final rates = tradeIntelRatePairLine(item);
    final src = tradeIntelSourceLine(item);
    if (qty.isEmpty && rates.isEmpty && src.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (qty.isNotEmpty)
              Text(
                qty,
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
            if (rates.isNotEmpty) ...[
              if (qty.isNotEmpty) const SizedBox(height: 6),
              Text(
                rates,
                style: tt.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
            if (src.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                src,
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.25,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogItemDefaultParties extends StatelessWidget {
  const _CatalogItemDefaultParties({required this.item, required this.ref});

  final Map<String, dynamic> item;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final supIds = (item['default_supplier_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    final brokIds = (item['default_broker_ids'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];
    if (supIds.isEmpty && brokIds.isEmpty) return const SizedBox.shrink();

    final sAsync = ref.watch(suppliersListProvider);
    final bAsync = ref.watch(brokersListProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (supIds.isNotEmpty) ...[
            const _ItemSectionLabel(label: 'Default suppliers'),
            const SizedBox(height: 6),
            sAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (rows) {
                final list =
                    rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                final byId = {for (final s in list) s['id']?.toString(): s};
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final id in supIds)
                      _DefaultPartyLine(
                        name: (byId[id]?['name'] ?? id).toString(),
                        phone: byId[id]?['phone']?.toString(),
                      ),
                  ],
                );
              },
            ),
          ],
          if (brokIds.isNotEmpty) ...[
            const SizedBox(height: 10),
            const _ItemSectionLabel(label: 'Default brokers'),
            const SizedBox(height: 6),
            bAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, __) => const SizedBox.shrink(),
              data: (rows) {
                final list =
                    rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
                final byId = {for (final b in list) b['id']?.toString(): b};
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final id in brokIds)
                      _DefaultPartyLine(
                        name: (byId[id]?['name'] ?? id).toString(),
                        phone: byId[id]?['phone']?.toString(),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _DefaultPartyLine extends StatelessWidget {
  const _DefaultPartyLine({required this.name, this.phone});

  final String name;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          if (phone != null && phone!.trim().isNotEmpty)
            Text(
              phone!,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
        ],
      ),
    );
  }
}
