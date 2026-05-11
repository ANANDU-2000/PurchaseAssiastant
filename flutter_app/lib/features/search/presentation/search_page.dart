import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/trade_intel_cards.dart';

const Duration _unifiedSearchTtl = Duration(seconds: 12);
const int _unifiedSearchCacheMaxEntries = 40;

final Map<String, ({DateTime at, Map<String, dynamic> data})> _unifiedSearchCache =
    {};

String _unifiedSearchCacheKey(String businessId, String query) =>
    '$businessId|${query.trim().toLowerCase()}';

/// Server-backed unified search (catalog items, catalog types, trade bills, suppliers).
final unifiedSearchProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, q) async {
    final session = ref.watch(sessionProvider);
    if (session == null || q.trim().isEmpty) {
      return {
        'catalog_items': <dynamic>[],
        'suppliers': <dynamic>[],
        'brokers': <dynamic>[],
        'catalog_subcategories': <dynamic>[],
        'recent_purchases': <dynamic>[],
      };
    }
    final bid = session.primaryBusiness.id;
    final key = _unifiedSearchCacheKey(bid, q);
    final now = DateTime.now();
    final hit = _unifiedSearchCache[key];
    if (hit != null && now.difference(hit.at) < _unifiedSearchTtl) {
      return hit.data;
    }
    final data = await ref.read(hexaApiProvider).unifiedSearch(
          businessId: bid,
          q: q.trim(),
        );
    _unifiedSearchCache[key] = (at: now, data: data);
    while (_unifiedSearchCache.length > _unifiedSearchCacheMaxEntries) {
      String? oldestK;
      DateTime? oldestT;
      for (final e in _unifiedSearchCache.entries) {
        if (oldestT == null || e.value.at.isBefore(oldestT)) {
          oldestT = e.value.at;
          oldestK = e.key;
        }
      }
      if (oldestK != null) _unifiedSearchCache.remove(oldestK);
    }
    return data;
  },
);

double? _toD(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

String _fmtInr(dynamic v, {int digits = 2}) {
  final n = _toD(v);
  if (n == null) return '—';
  return NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: digits,
  ).format(n);
}

String _fmtQty(dynamic v) {
  final n = _toD(v);
  if (n == null) return '—';
  if (n == n.roundToDouble()) return n.round().toString();
  return n.toStringAsFixed(2);
}

List<Map<String, dynamic>> _asMapListSkipBad(String key, Map<String, dynamic> data) {
  final raw = data[key];
  if (raw is! List) return [];
  final out = <Map<String, dynamic>>[];
  for (final e in raw) {
    if (e is Map) out.add(Map<String, dynamic>.from(e));
  }
  return out;
}

/// Align with trade reports / dashboard: omit soft-deleted, cancelled, and drafts.
bool _purchaseVisibleInUnifiedSearchHints(Map<String, dynamic> p) {
  final s = (p['status'] ?? '').toString().toLowerCase().trim();
  return s != 'deleted' && s != 'cancelled' && s != 'draft';
}

Map<String, dynamic>? _pickPurchaseLine(Map<String, dynamic> p, String q) {
  final lines = (p['lines'] as List<dynamic>?) ?? [];
  for (final raw in lines) {
    if (raw is! Map) continue;
    final m = Map<String, dynamic>.from(raw);
    final nm = (m['item_name'] ?? '').toString().toLowerCase();
    if (q.isNotEmpty && nm.contains(q)) return m;
  }
  if (lines.isNotEmpty && lines.first is Map) {
    return Map<String, dynamic>.from(lines.first as Map);
  }
  return null;
}

String _purchaseLineSummary(Map<String, dynamic> line) {
  final nm = line['item_name']?.toString() ?? 'Line';
  final qty = _fmtQty(line['qty']);
  final unit = line['unit']?.toString() ?? '';
  final pr = line['purchase_rate'];
  final lc = line['landing_cost'];
  final prN = _toD(pr);
  final rate = prN != null && prN > 0
      ? 'Rate ${_fmtInr(pr)}'
      : 'Landing ${_fmtInr(lc)}';
  return '$nm · $qty $unit · $rate';
}

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _debounced = '';
  String _section = 'all';

  static const _sections = {'all', 'types', 'items', 'bills', 'suppliers', 'contacts'};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sec = GoRouterState.of(context).uri.queryParameters['section'];
      if (sec != null && _sections.contains(sec)) {
        setState(() => _section = sec);
      }
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final next = v.trim();
      if (next == _debounced) return;
      setState(() => _debounced = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final q = _debounced.toLowerCase();
    final searchAsync = q.isNotEmpty
        ? ref.watch(unifiedSearchProvider(_debounced))
        : const AsyncValue<Map<String, dynamic>>.data({});

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/home'),
        ),
        title: const Text('Search'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          SearchBar(
            focusNode: _focus,
            controller: _controller,
            hintText: 'Item, type, bill, supplier, HSN…',
            textInputAction: TextInputAction.search,
            textStyle: const WidgetStatePropertyAll(TextStyle()),
            leading: const Icon(Icons.search_rounded),
            trailing: [
              if (_controller.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    _controller.clear();
                    setState(() => _debounced = '');
                    _scheduleSearch('');
                  },
                ),
            ],
            onChanged: (v) {
              setState(() {});
              _scheduleSearch(v);
            },
          ),
          const SizedBox(height: 16),
          if (q.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text(
                'Search catalog items (name, HSN, code, category, catalog type), '
                'recent purchase bills, suppliers, and brokers.',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            )
          else
            searchAsync.when(
              skipLoadingOnReload: true,
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => FriendlyLoadError(
                message: 'Search failed',
                onRetry: () =>
                    ref.invalidate(unifiedSearchProvider(_debounced)),
              ),
              data: (data) {
                final rawItems = _asMapListSkipBad('catalog_items', data);
                final suppliers = _asMapListSkipBad('suppliers', data);
                final brokers = _asMapListSkipBad('brokers', data);
                final types = _asMapListSkipBad('catalog_subcategories', data);
                final bills = _asMapListSkipBad('recent_purchases', data)
                    .where(_purchaseVisibleInUnifiedSearchHints)
                    .toList();
                final fuzzyItems = data['fuzzy_catalog_used'] == true;
                final fuzzySup = data['fuzzy_suppliers_used'] == true;
                final fuzzyBro = data['fuzzy_brokers_used'] == true;

                // Enrich catalog item hits with last-line qty/kg from matched recent purchases
                // so the UI can show "last bags/kg" even when the server only returns prices.
                int ymdKey(Object? dtRaw) {
                  if (dtRaw is String && dtRaw.length >= 10) {
                    final s = dtRaw.substring(0, 10).replaceAll('-', '');
                    return int.tryParse(s) ?? 0;
                  }
                  return 0;
                }

                final lastLineByItemId = <String, Map<String, dynamic>>{};
                final lastDateKeyByItemId = <String, int>{};
                final lastDateStringByItemId = <String, String>{};
                final lastBillHidByItemId = <String, String>{};
                for (final p in bills) {
                  final dtK = ymdKey(p['purchase_date']);
                  final dtStr = p['purchase_date']?.toString() ?? '';
                  final hid = p['human_id']?.toString() ?? '';
                  final lines = (p['lines'] is List) ? (p['lines'] as List) : const [];
                  for (final raw in lines) {
                    if (raw is! Map) continue;
                    final ln = Map<String, dynamic>.from(raw);
                    final cid = ln['catalog_item_id']?.toString() ?? '';
                    if (cid.isEmpty) continue;
                    final prevK = lastDateKeyByItemId[cid] ?? 0;
                    if (dtK >= prevK) {
                      lastDateKeyByItemId[cid] = dtK;
                      lastLineByItemId[cid] = ln;
                      if (dtStr.length >= 10) {
                        lastDateStringByItemId[cid] = dtStr.substring(0, 10);
                      }
                      if (hid.isNotEmpty) lastBillHidByItemId[cid] = hid;
                    }
                  }
                }

                final items = rawItems.map((m) {
                  final id = m['id']?.toString() ?? '';
                  if (id.isEmpty) return m;
                  if (m['last_line_qty'] != null || m['last_line_weight_kg'] != null) {
                    return m;
                  }
                  final ln = lastLineByItemId[id];
                  if (ln == null) return m;
                  final next = Map<String, dynamic>.from(m);
                  next['last_line_qty'] = ln['qty'];
                  next['last_line_unit'] = ln['unit'];
                  next['last_line_weight_kg'] = ln['total_weight_kg'] ?? ln['total_weight'];
                  next['kg_per_unit'] = ln['kg_per_unit'] ?? ln['default_kg_per_bag'];
                  // Prefer explicit per-kg rate if present.
                  next['purchase_rate_dim'] = (ln['landing_cost_per_kg'] != null || ln['kg_per_unit'] != null) ? 'kg' : (ln['unit'] ?? '');
                  next['last_purchase_price'] = ln['landing_cost_per_kg'] ?? ln['purchase_rate'] ?? ln['landing_cost'];
                  next['last_selling_rate'] = ln['selling_rate'] ?? ln['selling_cost'];
                  next['selling_rate_dim'] = next['purchase_rate_dim'];
                  final bh = lastBillHidByItemId[id];
                  if (bh != null && bh.isNotEmpty) {
                    next['last_purchase_human_id'] = bh;
                  }
                  final dateStr = lastDateStringByItemId[id];
                  if (dateStr != null) next['last_purchase_date'] = dateStr;
                  return next;
                }).toList();
                final contactHits = suppliers.length + brokers.length;
                final sectionCounts = <String, int>{
                  'types': types.length,
                  'items': items.length,
                  'bills': bills.length,
                  'suppliers': suppliers.length,
                  'contacts': contactHits,
                };
                final hasAny = types.isNotEmpty ||
                    items.isNotEmpty ||
                    bills.isNotEmpty ||
                    suppliers.isNotEmpty ||
                    brokers.isNotEmpty;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (fuzzyItems || fuzzySup || fuzzyBro)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          [
                            if (fuzzyItems)
                              'No exact item title match — showing close catalog matches. '
                                  'Do not trust rates until you open the item.',
                            if (fuzzySup)
                              'No exact supplier name match — showing close supplier matches.',
                            if (fuzzyBro)
                              'No exact broker name match — showing close broker matches.',
                          ].join(' '),
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _section == 'all',
                          onSelected: (_) => setState(() => _section = 'all'),
                        ),
                        ChoiceChip(
                          label: Text('Types (${sectionCounts['types']})'),
                          selected: _section == 'types',
                          onSelected: (_) =>
                              setState(() => _section = 'types'),
                        ),
                        ChoiceChip(
                          label: Text('Items (${sectionCounts['items']})'),
                          selected: _section == 'items',
                          onSelected: (_) =>
                              setState(() => _section = 'items'),
                        ),
                        ChoiceChip(
                          label: Text('Bills (${sectionCounts['bills']})'),
                          selected: _section == 'bills',
                          onSelected: (_) =>
                              setState(() => _section = 'bills'),
                        ),
                        ChoiceChip(
                          label:
                              Text('Suppliers (${sectionCounts['suppliers']})'),
                          selected: _section == 'suppliers',
                          onSelected: (_) =>
                              setState(() => _section = 'suppliers'),
                        ),
                        ChoiceChip(
                          label: Text('Contacts (${sectionCounts['contacts']})'),
                          selected: _section == 'contacts',
                          onSelected: (_) =>
                              setState(() => _section = 'contacts'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (!hasAny)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'No matches in catalog, bills, suppliers, or brokers for this query.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (_section == 'all' || _section == 'types') ...[
                      Text(
                        'Catalog types',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (types.isEmpty)
                        Text(
                          'No matching category / subcategory (type) names.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...types.map((m) {
                          final tid = m['id']?.toString() ?? '';
                          final cid = m['category_id']?.toString() ?? '';
                          final tname = m['name']?.toString() ?? '—';
                          final cname = m['category_name']?.toString() ?? '';
                          final typeName = tname.toLowerCase();
                          final matchingItemIds = items
                              .where(
                                (it) =>
                                    (it['category_name'] ??
                                            it['type_name'] ??
                                            '')
                                        .toString()
                                        .toLowerCase() ==
                                    typeName,
                              )
                              .map((it) => it['id']?.toString() ?? '')
                              .where((id) => id.isNotEmpty)
                              .toSet();
                          var typeTotalBags = 0.0;
                          var typeTotalKg = 0.0;
                          for (final id in matchingItemIds) {
                            final ln = lastLineByItemId[id];
                            if (ln == null) continue;
                            final qty = _toD(ln['qty']) ?? 0;
                            final unit =
                                ln['unit']?.toString().toLowerCase() ?? '';
                            if (unit == 'bag' || unit == 'sack') {
                              typeTotalBags += qty;
                            }
                            if (unit == 'kg') typeTotalKg += qty;
                          }
                          final parts = <String>[];
                          if (typeTotalBags > 0) {
                            parts.add('${_fmtQty(typeTotalBags)} bags');
                          }
                          if (typeTotalKg > 0) {
                            parts.add('${_fmtQty(typeTotalKg)} kg');
                          }
                          final summaryText =
                              parts.isEmpty ? null : parts.join(' · ');
                          final sub = cname.isEmpty
                              ? 'Catalog type'
                              : 'Under $cname';
                          final subBody = summaryText != null
                              ? '$sub\n$summaryText'
                              : sub;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            isThreeLine: summaryText != null,
                            leading: Icon(Icons.category_outlined,
                                color: cs.primary),
                            title: Text(tname),
                            subtitle: Text(
                              subBody,
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: tid.isEmpty || cid.isEmpty
                                ? null
                                : () => context.push(
                                      '/catalog/category/$cid/type/$tid',
                                    ),
                          );
                        }),
                      const SizedBox(height: 20),
                    ],
                    if (_section == 'all' || _section == 'items') ...[
                      Text(
                        'Catalog items',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (items.isEmpty)
                        Text(
                          'No matching catalog items.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...items.map((m) {
                          final id = m['id']?.toString() ?? '';
                          return TradeIntelCatalogSearchTile(
                            item: m,
                            fuzzyNameMatch: fuzzyItems,
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/catalog/item/$id'),
                          );
                        }),
                      const SizedBox(height: 20),
                    ],
                    if (_section == 'all' || _section == 'bills') ...[
                      Text(
                        'Recent purchase bills',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (bills.isEmpty)
                        Text(
                          'No bills matched (try item name, supplier, or bill id).',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...bills.map((p) {
                          final id = p['id']?.toString() ?? '';
                          final hid = p['human_id']?.toString() ?? '';
                          final dtRaw = p['purchase_date'];
                          String dateTxt = '';
                          if (dtRaw is String && dtRaw.length >= 10) {
                            dateTxt = dtRaw.substring(0, 10);
                          } else if (dtRaw != null) {
                            dateTxt = dtRaw.toString();
                          }
                          final sup =
                              p['supplier_name']?.toString() ?? 'Supplier';
                          final line = _pickPurchaseLine(p, q);
                          final lineTxt = line != null
                              ? _purchaseLineSummary(line)
                              : '';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            isThreeLine: lineTxt.isNotEmpty,
                            leading: Icon(Icons.receipt_long_outlined,
                                color: cs.secondary),
                            title: Text(
                              hid.isEmpty ? 'Purchase' : hid,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  [dateTxt, sup]
                                      .where((s) => s.isNotEmpty)
                                      .join(' · '),
                                  style: tt.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                if (lineTxt.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      lineTxt,
                                      style: tt.bodySmall?.copyWith(
                                        color: cs.onSurface,
                                        height: 1.35,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () =>
                                    context.push('/purchase/detail/$id'),
                          );
                        }),
                      const SizedBox(height: 20),
                    ],
                    if (_section == 'all' || _section == 'suppliers') ...[
                      Text(
                        'Suppliers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (suppliers.isEmpty)
                        Text(
                          'No matching suppliers.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...suppliers.map((m) {
                          final id = m['id']?.toString() ?? '';
                          final name = m['name']?.toString() ?? 'Supplier';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.storefront_outlined,
                                color: cs.primary),
                            title: Text(name),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/supplier/$id'),
                          );
                        }),
                    ],
                    if (_section == 'all' && brokers.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Brokers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...brokers.map((m) {
                        final id = m['id']?.toString() ?? '';
                        final name = m['name']?.toString() ?? 'Broker';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.handshake_outlined,
                              color: cs.secondary),
                          title: Text(name),
                          trailing:
                              const Icon(Icons.chevron_right_rounded),
                          onTap: id.isEmpty
                              ? null
                              : () => context.push('/broker/$id'),
                        );
                      }),
                    ],
                    if (_section == 'contacts') ...[
                      Text(
                        'Contacts',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Suppliers and brokers (same hub as Contacts → search).',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Suppliers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (suppliers.isEmpty)
                        Text(
                          'No matching suppliers.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...suppliers.map((m) {
                          final id = m['id']?.toString() ?? '';
                          final name = m['name']?.toString() ?? 'Supplier';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.storefront_outlined,
                                color: cs.primary),
                            title: Text(name),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/supplier/$id'),
                          );
                        }),
                      const SizedBox(height: 12),
                      Text(
                        'Brokers',
                        style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (brokers.isEmpty)
                        Text(
                          'No matching brokers.',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        )
                      else
                        ...brokers.map((m) {
                          final id = m['id']?.toString() ?? '';
                          final name = m['name']?.toString() ?? 'Broker';
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.handshake_outlined,
                                color: cs.secondary),
                            title: Text(name),
                            trailing:
                                const Icon(Icons.chevron_right_rounded),
                            onTap: id.isEmpty
                                ? null
                                : () => context.push('/broker/$id'),
                          );
                        }),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
