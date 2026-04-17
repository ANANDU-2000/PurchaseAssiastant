import 'package:dio/dio.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/bag_default_unit_hint.dart';

class CatalogItemDetailPage extends ConsumerStatefulWidget {
  const CatalogItemDetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<CatalogItemDetailPage> createState() =>
      _CatalogItemDetailPageState();
}

class _CatalogItemDetailPageState extends ConsumerState<CatalogItemDetailPage> {
  late ({String from, String to}) _range;

  @override
  void initState() {
    super.initState();
    _range = catalogInsightsDefaultRange();
  }

  String _insightKey() => '${widget.itemId}|${_range.from}|${_range.to}';

  String _inr(num? n) {
    if (n == null) return '—';
    return NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);
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
                DropdownButtonFormField<String?>(
                  key: ValueKey(unit),
                  initialValue: unit,
                  decoration: const InputDecoration(
                    labelText: 'Default unit (optional)',
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('—')),
                    DropdownMenuItem(value: 'kg', child: Text('kg')),
                    DropdownMenuItem(value: 'bag', child: Text('bag')),
                    DropdownMenuItem(value: 'box', child: Text('box')),
                    DropdownMenuItem(value: 'piece', child: Text('piece')),
                  ],
                  onChanged: (v) => setSt(() => unit = v),
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
    setState(() => _range = catalogInsightsDefaultRange());
    ref.invalidate(catalogItemDetailProvider(widget.itemId));
    ref.invalidate(catalogItemInsightsProvider(_insightKey()));
    ref.invalidate(catalogItemLinesProvider(_insightKey()));
    ref.invalidate(catalogVariantsProvider(widget.itemId));
    await ref.read(catalogItemDetailProvider(widget.itemId).future);
  }

  Future<void> _addVariant() async {
    final ctrl = TextEditingController();
    final kg = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New variant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: ctrl,
                decoration:
                    const InputDecoration(labelText: 'Name (e.g. 1L, 5L)')),
            const SizedBox(height: 8),
            TextField(
              controller: kg,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Default kg/bag (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final kgVal = double.tryParse(kg.text.trim());
    try {
      await ref.read(hexaApiProvider).createCatalogVariant(
            businessId: session.primaryBusiness.id,
            itemId: widget.itemId,
            name: ctrl.text.trim(),
            defaultKgPerBag: kgVal,
          );
      ref.invalidate(catalogVariantsProvider(widget.itemId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Variant added')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${e.response?.data ?? e}')));
      }
    }
  }

  Future<void> _editVariant(Map<String, dynamic> v) async {
    final id = v['id']?.toString() ?? '';
    final ctrl = TextEditingController(text: v['name']?.toString() ?? '');
    final kg = TextEditingController(
      text: v['default_kg_per_bag'] != null
          ? v['default_kg_per_bag'].toString()
          : '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit variant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: ctrl,
                decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: kg,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Default kg/bag (optional)'),
            ),
          ],
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
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final kgVal =
        kg.text.trim().isEmpty ? null : double.tryParse(kg.text.trim());
    try {
      await ref.read(hexaApiProvider).updateCatalogVariant(
            businessId: session.primaryBusiness.id,
            variantId: id,
            name: ctrl.text.trim(),
            defaultKgPerBag: kgVal,
          );
      ref.invalidate(catalogVariantsProvider(widget.itemId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(e))));
      }
    }
  }

  Future<void> _deleteVariant(Map<String, dynamic> v) async {
    final id = v['id']?.toString() ?? '';
    final name = v['name']?.toString() ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete variant?'),
        content: Text('Delete “$name”?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteCatalogVariant(
            businessId: session.primaryBusiness.id,
            variantId: id,
          );
      ref.invalidate(catalogVariantsProvider(widget.itemId));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    } on DioException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${e.response?.data ?? e}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemAsync = ref.watch(catalogItemDetailProvider(widget.itemId));
    final insAsync = ref.watch(catalogItemInsightsProvider(_insightKey()));
    final linesAsync = ref.watch(catalogItemLinesProvider(_insightKey()));
    final varsAsync = ref.watch(catalogVariantsProvider(widget.itemId));
    final catsAsync = ref.watch(itemCategoriesListProvider);

    return Scaffold(
      appBar: AppBar(
        title: itemAsync.when(
          data: (m) => Text(m['name']?.toString() ?? 'Item',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          loading: () => const Text('Item'),
          error: (_, __) => const Text('Catalog item'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Price intelligence (name-based)',
            onPressed: () {
              final m = itemAsync.valueOrNull;
              final name = m?['name']?.toString() ?? '';
              if (name.isEmpty) return;
              context.push('/item-analytics/${Uri.encodeComponent(name)}');
            },
          ),
        ],
      ),
      floatingActionButton: itemAsync.hasValue
          ? FloatingActionButton.extended(
              onPressed: _addVariant,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Variant'),
            )
          : null,
      body: itemAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
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
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                if (catName != null && catName.isNotEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.category_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      'In category: $catName',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                    ),
                    subtitle: Text(
                      'View items in this category',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(
                      '/contacts/category?name=${Uri.encodeComponent(catName!)}',
                    ),
                  ),
                const SizedBox(height: 8),
                insAsync.when(
                  loading: () => const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator())),
                  error: (_, __) => FriendlyLoadError(
                    onRetry: () => ref
                        .invalidate(catalogItemInsightsProvider(_insightKey())),
                  ),
                  data: (ins) {
                    final lc = ins['line_count'];
                    final ec = ins['entry_count'];
                    final tp = ins['total_profit'];
                    final al = ins['avg_landing'];
                    final as = ins['avg_selling'];
                    final ld = ins['last_entry_date']?.toString();
                    final pm = ins['profit_margin_pct'];
                    final itemName = item['name']?.toString() ?? '';
                    final intelKey =
                        '$itemName|${_num(al)?.toStringAsFixed(4) ?? ''}';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Consumer(
                          builder: (context, ref, _) {
                            final pip = ref.watch(
                                catalogItemPriceIntelProvider(intelKey));
                            return pip.when(
                              loading: () => const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: LinearProgressIndicator(),
                              ),
                              error: (_, __) => const SizedBox.shrink(),
                              data: (p) => _PriceIntelDecisionCard(
                                pip: p,
                                inr: _inr,
                                onAddPurchase: () =>
                                    context.push('/purchase/new'),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Key numbers',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                        ),
                        const SizedBox(height: 8),
                        _GoldenMetricStrip(
                          profit: _inr(_num(tp)),
                          avgLanding: _inr(_num(al)),
                          marginPct: pm == null
                              ? '—'
                              : '${(pm as num).toStringAsFixed(1)}%',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Details',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                        ),
                        const SizedBox(height: 8),
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
                        Text(
                          'Lines $lc · Purchases $ec · Avg sell ${_inr(_num(as))}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12,
                              ),
                        ),
                        if (ld != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Last purchase $ld · Period ${_range.from} → ${_range.to}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                            ),
                          )
                        else
                          Text(
                            'Period ${_range.from} → ${_range.to}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontSize: 12,
                                ),
                          ),
                        const SizedBox(height: 12),
                        linesAsync.when(
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                          data: (rows) =>
                              _LandingTrendMiniChart(rows: rows, inr: _inr),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Text('Variants',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                varsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => FriendlyLoadError(
                    onRetry: () =>
                        ref.invalidate(catalogVariantsProvider(widget.itemId)),
                  ),
                  data: (vs) {
                    if (vs.isEmpty) {
                      return Text(
                        'No variants yet. Variants distinguish pack sizes (1L vs 5L) under this item.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: HexaColors.textSecondary),
                      );
                    }
                    return Column(
                      children: vs.map((v) {
                        final name = v['name']?.toString() ?? '';
                        final kg = v['default_kg_per_bag'];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle:
                                kg != null ? Text('Default $kg kg/bag') : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => _editVariant(v)),
                                IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _deleteVariant(v)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  'Purchase history',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 8),
                linesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => FriendlyLoadError(
                    onRetry: () =>
                        ref.invalidate(catalogItemLinesProvider(_insightKey())),
                  ),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return Text(
                        'No purchase lines linked to this catalog item in this period. Record purchases with this item picked from the catalog.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: HexaColors.textSecondary),
                      );
                    }
                    return _PurchaseHistoryTable(
                      rows: rows,
                      inr: _inr,
                      readNum: _num,
                      onRowTap: (eid) {
                        if (eid.isNotEmpty) context.push('/entry/$eid');
                      },
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  num? _num(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }
}

/// Compact metrics: number first, label second — target ~76px height.
class _GoldenMetricStrip extends StatelessWidget {
  const _GoldenMetricStrip({
    required this.profit,
    required this.avgLanding,
    required this.marginPct,
  });

  final String profit;
  final String avgLanding;
  final String marginPct;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget cell(String value, String label) {
      return Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 68, maxHeight: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.9),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cell(profit, 'Total profit'),
        const SizedBox(width: 8),
        cell(avgLanding, 'Avg landing'),
        const SizedBox(width: 8),
        cell(marginPct, 'Margin %'),
      ],
    );
  }
}

/// Dense history: header + aligned rows (no card stack per row).
class _PurchaseHistoryTable extends StatelessWidget {
  const _PurchaseHistoryTable({
    required this.rows,
    required this.inr,
    required this.readNum,
    required this.onRowTap,
  });

  final List<Map<String, dynamic>> rows;
  final String Function(num?) inr;
  final num? Function(dynamic v) readNum;
  final void Function(String entryId) onRowTap;

  String _fmtDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    final d = DateTime.tryParse(raw);
    if (d == null) return raw.split('T').first;
    return DateFormat.MMMd().format(d);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final border = cs.outlineVariant.withValues(alpha: 0.85);

    TextStyle? hdr = tt.labelSmall?.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant,
    );
    TextStyle? cell = tt.bodySmall?.copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w600,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text('Date', style: hdr),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Qty', style: hdr),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Landing',
                      style: hdr,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'P/L',
                      style: hdr,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: border),
            ...rows.map((r) {
              final eid = r['entry_id']?.toString() ?? '';
              final rawD = r['entry_date']?.toString();
              return InkWell(
                onTap: eid.isEmpty ? null : () => onRowTap(eid),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(_fmtDate(rawD), style: cell),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${r['qty'] ?? ''} ${r['unit'] ?? ''}'.trim(),
                          style: cell,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          inr(readNum(r['landing_cost'])),
                          style: cell,
                          textAlign: TextAlign.right,
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          inr(readNum(r['profit'])),
                          style: cell?.copyWith(
                            color: HexaColors.profit,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _PriceIntelDecisionCard extends StatelessWidget {
  const _PriceIntelDecisionCard({
    required this.pip,
    required this.inr,
    this.onAddPurchase,
  });

  final Map<String, dynamic> pip;
  final String Function(num?) inr;
  final VoidCallback? onAddPurchase;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final conf = pip['confidence'];
    if (conf is num && conf <= 0) {
      return Card(
        color: cs.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Add a few more purchases with this item name to unlock landing benchmarks and supplier comparison.',
            style: tt.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
      );
    }
    final avg = pip['avg'];
    final last = pip['last_price'];
    final low = pip['low'];
    final high = pip['high'];
    final pos = pip['position_pct'];
    final hints = (pip['decision_hints'] as List?) ?? [];
    final sups = (pip['supplier_compare'] as List?) ?? [];
    Map<String, dynamic>? bestSup;
    double? bestVal;
    for (final s in sups) {
      if (s is! Map) continue;
      final m = Map<String, dynamic>.from(s);
      final av = m['avg_landing'];
      final v = av is num ? av.toDouble() : double.tryParse('$av');
      if (v == null) continue;
      if (bestVal == null || v < bestVal) {
        bestVal = v;
        bestSup = m;
      }
    }

    return Card(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Decision',
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            if (bestSup != null && bestVal != null)
              Text(
                'Best supplier: ${bestSup['name']?.toString() ?? '—'} — ${inr(bestVal)}/unit',
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  height: 1.2,
                  color: cs.onSurface,
                ),
              ),
            if (avg is num &&
                bestVal != null &&
                avg.toDouble() > bestVal) ...[
              const SizedBox(height: 6),
              Text(
                'You pay ${inr(avg.toDouble() - bestVal)} more than best on average',
                style: tt.labelLarge?.copyWith(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Avg ${avg is num ? inr(avg) : '—'} · Last ${last is num ? inr(last) : '—'} · Low ${low is num ? inr(low) : '—'} · High ${high is num ? inr(high) : '—'}',
              style: tt.labelSmall?.copyWith(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (pos is num) ...[
              const SizedBox(height: 10),
              Text(
                pos >= 66
                    ? 'Latest buy is on the high side — negotiate or switch supplier.'
                    : (pos <= 33
                        ? 'You are buying at a good price vs your range.'
                        : 'Landing is mid-range vs your history.'),
                style: tt.bodySmall?.copyWith(
                  color: pos >= 66 ? HexaColors.warning : cs.onSurface,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pos / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: pos >= 66 ? HexaColors.warning : HexaColors.accentInfo,
                ),
              ),
            ],
            if (hints.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...hints.take(2).map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $h',
                        style: tt.bodySmall?.copyWith(
                          height: 1.35,
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
            ],
            if (sups.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Suppliers (avg landing)',
                style: tt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              ...sups.take(6).map((s) {
                if (s is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(s);
                final n = m['name']?.toString() ?? '';
                final av = m['avg_landing'];
                final avn = av is num ? av.toDouble() : double.tryParse('$av');
                final isBest = bestSup != null &&
                    n == bestSup['name']?.toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          n,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight:
                                isBest ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (isBest)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            'Best',
                            style: tt.labelSmall?.copyWith(
                              color: HexaColors.profit,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      Text(
                        avn != null ? inr(avn) : '—',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            if (onAddPurchase != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onAddPurchase,
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 20),
                label: const Text('Add purchase'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LandingTrendMiniChart extends StatelessWidget {
  const _LandingTrendMiniChart({
    required this.rows,
    required this.inr,
  });

  final List<Map<String, dynamic>> rows;
  final String Function(num?) inr;

  static num? _parse(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    if (rows.length < 2) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pts = <({DateTime? d, double y})>[];
    for (final r in rows) {
      final raw = r['entry_date']?.toString();
      final lc = _parse(r['landing_cost']);
      if (lc == null) continue;
      DateTime? dt;
      if (raw != null) {
        dt = DateTime.tryParse(raw);
      }
      pts.add((d: dt, y: lc.toDouble()));
    }
    pts.sort((a, b) {
      if (a.d == null && b.d == null) return 0;
      if (a.d == null) return -1;
      if (b.d == null) return 1;
      return a.d!.compareTo(b.d!);
    });
    if (pts.length < 2) return const SizedBox.shrink();
    final spots = <FlSpot>[];
    var minY = pts.first.y;
    var maxY = pts.first.y;
    for (var i = 0; i < pts.length; i++) {
      final y = pts[i].y;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      spots.add(FlSpot(i.toDouble(), y));
    }
    final span = (maxY - minY).abs() < 1e-6 ? 1.0 : (maxY - minY);
    return Card(
      color: cs.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Landing trend (this period)',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: RepaintBoundary(
                child: LayoutBuilder(
                  builder: (context, c) {
                    if (c.maxWidth <= 0) return const SizedBox.shrink();
                    return LineChart(
                      LineChartData(
                        minY: minY - span * 0.08,
                        maxY: maxY + span * 0.08,
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: const LineTouchData(enabled: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: HexaColors.accentInfo,
                            barWidth: 2.5,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (a, b, c, d) =>
                                  FlDotCirclePainter(
                                radius: 3,
                                color: HexaColors.primaryNavy,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Oldest → newest · ${inr(minY)} – ${inr(maxY)}',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
