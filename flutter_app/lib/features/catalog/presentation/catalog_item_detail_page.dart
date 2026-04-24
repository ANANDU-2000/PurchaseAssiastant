import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/catalog/item_trade_history.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/services/reports_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';
import '../../../shared/widgets/search_picker_sheet.dart';

class CatalogItemDetailPage extends ConsumerStatefulWidget {
  const CatalogItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<CatalogItemDetailPage> createState() =>
      _CatalogItemDetailPageState();
}

class _CatalogItemDetailPageState extends ConsumerState<CatalogItemDetailPage> {
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
    final kgCtrl = TextEditingController(
      text: item['default_kg_per_bag'] != null
          ? item['default_kg_per_bag'].toString()
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('Default purchase unit'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  ),
                  const SizedBox(height: 8),
                  const BagDefaultUnitHint(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
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
      await ref.read(hexaApiProvider).updateCatalogItem(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            includeDefaultUnit: true,
            defaultUnit: unit,
            patchDefaultKgPerBag: unit == 'bag',
            defaultKgPerBag: kgParsed,
          );
      ref.invalidate(catalogItemDetailProvider(widget.itemId));
      ref.invalidate(tradePurchasesCatalogIntelProvider);
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
      kgCtrl.dispose();
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(catalogItemDetailProvider(widget.itemId));
    ref.invalidate(tradePurchasesCatalogIntelProvider);
    await ref.read(catalogItemDetailProvider(widget.itemId).future);
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
      final rows = hist
          .map(
            (r) => [
              df.format(r.purchaseDate),
              r.supplierName,
              '${_fmtNum(r.line.qty)} ${r.line.unit}',
              r.rateLabel().replaceAll('₹', 'Rs. '),
              _inr(r.lineTotal),
            ],
          )
          .toList();
      await shareItemPurchaseTradeHistoryPdf(
        business: biz,
        itemName: itemName,
        rows: rows,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF failed: $e')),
        );
      }
    }
  }

  void _openPurchasesForThisItem() {
    context.pushNamed(
      'purchase_new',
      queryParameters: {'catalogItemId': widget.itemId},
    );
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
        title: itemAsync.when(
          data: (m) => Text(
            m['name']?.toString() ?? 'Item',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          loading: () => const Text('Item'),
          error: (_, __) => const Text('Catalog item'),
        ),
      ),
      floatingActionButton: itemAsync.hasValue
          ? FloatingActionButton.extended(
              onPressed: _openPurchasesForThisItem,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('Add purchase'),
            )
          : null,
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
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
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
                if (hsn != null && hsn.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'HSN $hsn',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
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
                    final hist =
                        itemTradeHistoryRows(purchases, widget.itemId);
                    final intel = itemSupplierIntel(hist);
                    final recent = hist.take(5).toList();
                    final last = hist.isNotEmpty ? hist.first : null;
                    var qtySum = 0.0;
                    for (final r in hist) {
                      qtySum += r.line.qty;
                    }
                    final itemName = item['name']?.toString() ?? 'Item';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (last != null) ...[
                          const _ItemSectionLabel(label: 'Last purchase'),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      last.supplierName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (last.supplierPhone != null &&
                                        last.supplierPhone!.trim().isNotEmpty)
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                          alignment: Alignment.centerLeft,
                                        ),
                                        onPressed: () async {
                                          final raw =
                                              last.supplierPhone!.trim();
                                          final cleaned = raw.replaceAll(
                                              RegExp(r'[^\d+]'), '');
                                          final uri = Uri(
                                            scheme: 'tel',
                                            path: cleaned,
                                          );
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri);
                                          }
                                        },
                                        icon: const Icon(Icons.call_rounded,
                                            size: 18),
                                        label: Text(last.supplierPhone!),
                                      ),
                                    if (last.brokerName != null &&
                                        last.brokerName!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        'Broker: ${last.brokerName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                      if (last.brokerPhone != null &&
                                          last.brokerPhone!.trim().isNotEmpty)
                                        TextButton.icon(
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            visualDensity: VisualDensity.compact,
                                            alignment: Alignment.centerLeft,
                                          ),
                                          onPressed: () async {
                                            final raw =
                                                last.brokerPhone!.trim();
                                            final cleaned = raw.replaceAll(
                                                RegExp(r'[^\d+]'), '');
                                            final uri = Uri(
                                              scheme: 'tel',
                                              path: cleaned,
                                            );
                                            if (await canLaunchUrl(uri)) {
                                              await launchUrl(uri);
                                            }
                                          },
                                          icon: const Icon(
                                              Icons.call_rounded,
                                              size: 18),
                                          label: Text(last.brokerPhone!),
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Last: ${last.rateLabel()} · ${_inr(last.lineTotal)} · ${_fmtDate(last.purchaseDate.toIso8601String())}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: _StatChip(
                                label: 'Qty purchased',
                                value: _fmtNum(qtySum),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _StatChip(
                                label: 'Purchase lines',
                                value: '${hist.length}',
                              ),
                            ),
                          ],
                        ),
                        if (last == null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'No trade purchase lines linked to this item yet (each saved line needs a catalog item).',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const _ItemSectionLabel(
                            label: 'Recent history (last 5, trade)'),
                        const SizedBox(height: 6),
                        if (recent.isEmpty)
                          Text(
                            'No lines in latest 200 purchases.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          )
                        else ...[
                          _TradeHistoryHeaderRow(
                              cs: Theme.of(context).colorScheme),
                          for (final r in recent)
                            _TradeHistoryDataRow(
                              dateStr:
                                  _fmtDate(r.purchaseDate.toIso8601String()),
                              supplier: r.supplierName,
                              qtyUnit:
                                  '${_fmtNum(r.line.qty)} ${r.line.unit}',
                              rate: r.rateLabel(),
                              total: _inr(r.lineTotal),
                              cs: Theme.of(context).colorScheme,
                            ),
                        ],
                        const SizedBox(height: 16),
                        const _ItemSectionLabel(label: 'Supplier comparison'),
                        const SizedBox(height: 6),
                        if (intel.isEmpty)
                          Text(
                            'No supplier mix yet.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          )
                        else ...[
                          _SupplierIntelHeaderRow(
                              cs: Theme.of(context).colorScheme),
                          for (final s in intel)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      s.supplierName,
                                      style: TextStyle(
                                        fontWeight:
                                            supplierIntelIsBest(s, intel)
                                                ? FontWeight.w900
                                                : FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: Text(
                                      '${s.deals}',
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      s.avgLabel(),
                                      textAlign: TextAlign.end,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  if (supplierIntelIsBest(s, intel))
                                    const Padding(
                                      padding: EdgeInsets.only(left: 6),
                                      child: Text(
                                        'Best price',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: HexaColors.profit,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () =>
                              _exportItemPdf(itemName, hist),
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
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }
}

class _TradeHistoryHeaderRow extends StatelessWidget {
  const _TradeHistoryHeaderRow({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    TextStyle st() => Theme.of(context).textTheme.labelSmall!.copyWith(
          fontWeight: FontWeight.w800,
          color: cs.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text('Date', style: st())),
          Expanded(flex: 2, child: Text('Supplier', style: st())),
          Expanded(
            flex: 2,
            child: Text('Qty', style: st()),
          ),
          SizedBox(width: 72, child: Text('Rate', style: st(), textAlign: TextAlign.end)),
          SizedBox(
            width: 72,
            child: Text(
              'Total',
              style: st(),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _TradeHistoryDataRow extends StatelessWidget {
  const _TradeHistoryDataRow({
    required this.dateStr,
    required this.supplier,
    required this.qtyUnit,
    required this.rate,
    required this.total,
    required this.cs,
  });

  final String dateStr;
  final String supplier;
  final String qtyUnit;
  final String rate;
  final String total;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              dateStr,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              supplier,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              qtyUnit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              rate,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(
            width: 72,
            child: Text(
              total,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierIntelHeaderRow extends StatelessWidget {
  const _SupplierIntelHeaderRow({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final st = Theme.of(context).textTheme.labelSmall!.copyWith(
          fontWeight: FontWeight.w800,
          color: cs.onSurfaceVariant,
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text('Supplier', style: st)),
          SizedBox(width: 44, child: Text('Deals', style: st, textAlign: TextAlign.end)),
          Expanded(flex: 2, child: Text('Avg', style: st, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
