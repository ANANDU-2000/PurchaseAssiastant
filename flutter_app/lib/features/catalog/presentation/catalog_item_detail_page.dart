import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';

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
                    return Card(
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
                                _chip(context, 'Total profit', _inr(_num(tp))),
                                _chip(context, 'Avg landing', _inr(_num(al))),
                                _chip(context, 'Avg selling', _inr(_num(as))),
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
