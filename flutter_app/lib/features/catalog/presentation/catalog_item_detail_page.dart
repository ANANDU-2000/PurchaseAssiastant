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
                  Text(
                    catName,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: HexaColors.textSecondary),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
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
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
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
                  'Last ${_range.from} → ${_range.to}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
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
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Performance',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    _chip(context, 'Lines', '$lc'),
                                    _chip(context, 'Purchases', '$ec'),
                                    _chip(
                                        context, 'Total profit', _inr(_num(tp))),
                                    _chip(context, 'Avg landing', _inr(_num(al))),
                                    _chip(
                                        context, 'Avg selling', _inr(_num(as))),
                                    if (pm != null)
                                      _chip(context, 'Margin %',
                                          '${(pm as num).toStringAsFixed(1)}%'),
                                    if (ld != null)
                                      _chip(context, 'Last purchase', ld),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
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
                Text('Purchase history',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
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
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Qty')),
                          DataColumn(label: Text('Landing')),
                          DataColumn(label: Text('Selling')),
                          DataColumn(label: Text('Profit')),
                        ],
                        rows: rows.map((r) {
                          final eid = r['entry_id']?.toString() ?? '';
                          final d = r['entry_date']?.toString() ?? '';
                          return DataRow(
                            onSelectChanged: (_) {
                              if (eid.isNotEmpty) context.push('/entry/$eid');
                            },
                            cells: [
                              DataCell(Text(d)),
                              DataCell(Text('${r['qty']} ${r['unit']}')),
                              DataCell(Text(_inr(_num(r['landing_cost'])))),
                              DataCell(Text(_inr(_num(r['selling_price'])))),
                              DataCell(Text(_inr(_num(r['profit'])))),
                            ],
                          );
                        }).toList(),
                      ),
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

  Widget _chip(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _PriceIntelDecisionCard extends StatelessWidget {
  const _PriceIntelDecisionCard({
    required this.pip,
    required this.inr,
  });

  final Map<String, dynamic> pip;
  final String Function(num?) inr;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final conf = pip['confidence'];
    if (conf is num && conf <= 0) {
      return Card(
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Decisions · landing cost',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _miniMetric(context, 'Avg', avg is num ? inr(avg) : '—'),
                _miniMetric(context, 'Last', last is num ? inr(last) : '—'),
                _miniMetric(context, 'Best', low is num ? inr(low) : '—'),
                _miniMetric(context, 'Worst', high is num ? inr(high) : '—'),
              ],
            ),
            if (pos is num) ...[
              const SizedBox(height: 12),
              Text(
                pos >= 66
                    ? 'Latest landing is on the high side of your range'
                    : (pos <= 33
                        ? 'Latest landing is on the low side of your range'
                        : 'Latest landing is mid-range vs your history'),
                style: tt.labelSmall?.copyWith(
                  color: pos >= 66 ? HexaColors.warning : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
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
              ...hints.take(3).map(
                    (h) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.tips_and_updates_outlined,
                              size: 16, color: cs.tertiary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '$h',
                              style: tt.bodySmall?.copyWith(height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
            if (sups.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Suppliers (avg landing)',
                style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              ...sups.take(6).map((s) {
                if (s is! Map) return const SizedBox.shrink();
                final m = Map<String, dynamic>.from(s);
                final n = m['name']?.toString() ?? '';
                final av = m['avg_landing'];
                final avn = av is num ? av.toDouble() : double.tryParse('$av');
                final good = avg is num && avn != null && avn <= avg;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        good
                            ? Icons.check_circle_outline
                            : Icons.circle_outlined,
                        size: 18,
                        color: good ? HexaColors.profit : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(n, style: tt.bodyMedium)),
                      Text(
                        avn != null ? inr(avn) : '—',
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniMetric(BuildContext context, String k, String v) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            k,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
          ),
          Text(
            v,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
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
