import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/decision/trade_buy_verdict.dart';
import '../../../core/providers/business_write_revision.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
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
      ref.invalidate(catalogItemTradeSupplierPricesProvider(widget.itemId));
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
    ref.invalidate(catalogItemTradeSupplierPricesProvider(widget.itemId));
    await ref.read(catalogItemDetailProvider(widget.itemId).future);
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
      }
    });

    final itemAsync = ref.watch(catalogItemDetailProvider(widget.itemId));
    final tradeAsync =
        ref.watch(catalogItemTradeSupplierPricesProvider(widget.itemId));
    final catsAsync = ref.watch(itemCategoriesListProvider);

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
          final lastFromCatalog = _num(item['last_purchase_price']);
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
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 12,
                          ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push(
                      '/contacts/category?name=${Uri.encodeComponent(catName!)}',
                    ),
                  ),
                if (catName != null && catName.isNotEmpty) const SizedBox(height: 8),
                tradeAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => FriendlyLoadError(
                    message: 'Could not load trade prices',
                    onRetry: () => ref.invalidate(
                        catalogItemTradeSupplierPricesProvider(widget.itemId)),
                  ),
                  data: (raw) {
                    final suppliers = _parseSupplierRows(raw['suppliers']);
                    final lastFive = _parseDoubleList(raw['last_five_landing_prices']);
                    final avg = _asDouble(raw['avg_landing_from_trade']);
                    final lastLanded = lastFive.isNotEmpty
                        ? lastFive.first
                        : (lastFromCatalog is num
                            ? lastFromCatalog.toDouble()
                            : null);
                    double? bestLatest;
                    for (final s in suppliers) {
                      final v = s.landing;
                      if (v == null) continue;
                      if (bestLatest == null || v < bestLatest) bestLatest = v;
                    }
                    final verdict = tradeBuyVerdict(
                      lastLanded: lastLanded,
                      tradeAvg: avg,
                      bestLatest: bestLatest,
                    );
                    const maxRows = 8;
                    final show = suppliers.length > maxRows
                        ? suppliers.take(maxRows).toList()
                        : suppliers;
                    final rest = suppliers.length - show.length;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['name']?.toString() ?? 'Item',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 20,
                                      ),
                                ),
                                if (hsn != null && hsn.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'HSN $hsn',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _MetricCell(
                                        label: 'Last landed (trade)',
                                        value: _inr(lastLanded),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _MetricCell(
                                        label: 'Trade average',
                                        value: _inr(avg),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Card(
                          color: Theme.of(context).colorScheme.surface,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outlineVariant,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Decision',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  verdict.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        color: verdict.accent,
                                        letterSpacing: 0.5,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  verdict.detail,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                        height: 1.4,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _openPurchasesForThisItem,
                                  icon: const Icon(
                                    Icons.add_shopping_cart_rounded,
                                    size: 20,
                                  ),
                                  label: const Text('Add purchase'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Suppliers (latest trade)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                        ),
                        const SizedBox(height: 8),
                        if (show.isEmpty)
                          Text(
                            'No confirmed trade lines for this item yet.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          )
                        else
                          ...show.map(
                            (s) => _SupplierLadderRow(
                              name: s.name,
                              landing: s.landing,
                              unit: s.unit,
                              dateStr: s.dateRaw,
                              isBest: s.isBest,
                              inr: _inr,
                              onTap: s.id == null
                                  ? null
                                  : () => context.push('/supplier/${s.id}'),
                            ),
                          ),
                        if (rest > 0) ...[
                          const SizedBox(height: 6),
                          Text(
                            'And $rest more — open analytics for a full name-based breakdown.',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          'Last 5 landed prices (newest first)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                        ),
                        const SizedBox(height: 8),
                        if (lastFive.isEmpty)
                          Text(
                            '—',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          )
                        else
                          Text(
                            lastFive
                                .map((e) => _inr(e))
                                .join(' · '),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        const SizedBox(height: 16),
                        Text(
                          'Defaults',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
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
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () {
                            final name = item['name']?.toString() ?? '';
                            if (name.isEmpty) return;
                            context.push(
                              '/item-analytics/${Uri.encodeComponent(name)}',
                            );
                          },
                          child: const Text('Advanced analytics (name-based)'),
                        ),
                      ],
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

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: tt.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierRow {
  const _SupplierRow({
    required this.id,
    required this.name,
    required this.landing,
    required this.unit,
    required this.dateRaw,
    required this.isBest,
  });

  final String? id;
  final String name;
  final double? landing;
  final String? unit;
  final String? dateRaw;
  final bool isBest;
}

List<_SupplierRow> _parseSupplierRows(dynamic raw) {
  if (raw is! List) return [];
  final out = <_SupplierRow>[];
  for (final e in raw) {
    if (e is! Map) continue;
    final m = Map<String, dynamic>.from(e);
    out.add(
      _SupplierRow(
        id: m['supplier_id']?.toString(),
        name: m['supplier_name']?.toString() ?? '—',
        landing: _asDouble(m['landing_cost']),
        unit: m['unit']?.toString(),
        dateRaw: m['last_purchase_date']?.toString(),
        isBest: m['is_best'] == true,
      ),
    );
  }
  return out;
}

List<double> _parseDoubleList(dynamic raw) {
  if (raw is! List) return [];
  return raw
      .map((e) => e is num ? e.toDouble() : double.tryParse('$e'))
      .whereType<double>()
      .toList();
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

class _SupplierLadderRow extends StatelessWidget {
  const _SupplierLadderRow({
    required this.name,
    required this.landing,
    required this.unit,
    required this.dateStr,
    required this.isBest,
    required this.inr,
    this.onTap,
  });

  final String name;
  final double? landing;
  final String? unit;
  final String? dateStr;
  final bool isBest;
  final String Function(num?) inr;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    String dline = '';
    if (dateStr != null && dateStr!.isNotEmpty) {
      final d = DateTime.tryParse(dateStr!);
      dline = d == null
          ? dateStr!.split('T').first
          : DateFormat.yMMMd().format(d);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: tt.bodyLarge?.copyWith(
                          fontWeight: isBest ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                      if (dline.isNotEmpty)
                        Text(
                          dline,
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isBest)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      'BEST',
                      style: tt.labelSmall?.copyWith(
                        color: HexaColors.profit,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                Text(
                  '${inr(landing)}'
                  '${(unit != null && unit!.isNotEmpty) ? ' / $unit' : ''}',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
