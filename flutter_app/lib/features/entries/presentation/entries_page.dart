import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/entries_list_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/app_settings_action.dart';
import '../../../core/widgets/friendly_load_error.dart'
    show FriendlyLoadError, kFriendlyLoadNetworkSubtitle;
import '../../../shared/widgets/hexa_empty_state.dart';

class EntriesPage extends ConsumerStatefulWidget {
  const EntriesPage({super.key, this.requestSearchFocus = false});

  /// From home search tap: focus the purchase log search field.
  final bool requestSearchFocus;

  @override
  ConsumerState<EntriesPage> createState() => _EntriesPageState();
}

class _EntriesPageState extends ConsumerState<EntriesPage> {
  late final TextEditingController _searchCtrl;
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchCtrl =
        TextEditingController(text: ref.read(entrySearchQueryProvider));
    _searchCtrl.addListener(_onSearchChanged);
    if (widget.requestSearchFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _searchFocus.requestFocus();
      });
    }
  }

  void _onSearchChanged() {
    ref.read(entrySearchQueryProvider.notifier).state = _searchCtrl.text;
    setState(() {});
  }

  /// Text used for typo-tolerant client filter (search does not refetch the list).
  static String _entryFuzzyHaystack(
    Map<String, dynamic> e,
    Map<String, String> supplierNames,
  ) {
    final buf = StringBuffer();
    buf.write(_titleLine(e));
    buf.write(' ');
    final sid = e['supplier_id']?.toString();
    final sn = sid == null ? null : supplierNames[sid];
    if (sn != null && sn.isNotEmpty) {
      buf.write(sn);
      buf.write(' ');
    }
    final notes = e['notes']?.toString();
    if (notes != null && notes.trim().isNotEmpty) {
      buf.write(notes);
      buf.write(' ');
    }
    final lines = e['lines'];
    if (lines is List) {
      for (final li in lines) {
        if (li is! Map) continue;
        final n = li['item_name']?.toString();
        if (n != null && n.isNotEmpty) buf.write('$n ');
        final cat = li['category']?.toString();
        if (cat != null && cat.isNotEmpty) buf.write('$cat ');
      }
    }
    return buf.toString();
  }

  /// Extra hint in debug so local web devs know why XHR fails (connection refused).
  String _entriesLoadErrorSubtitle() {
    if (!kDebugMode) return kFriendlyLoadNetworkSubtitle;
    return '$kFriendlyLoadNetworkSubtitle\n\n'
        'Local dev: start the API (uvicorn on port 8000) or set API_BASE_URL '
        'to match where the backend listens.';
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  static String _titleLine(Map<String, dynamic> e) {
    final lines = e['lines'];
    if (lines is! List || lines.isEmpty) return 'Purchase entry';
    final first = lines.first;
    if (first is! Map) return 'Purchase entry';
    final name = first['item_name'] as String? ?? 'Item';
    final cat = first['category'] as String?;
    final head = (cat != null && cat.trim().isNotEmpty) ? '$name ($cat)' : name;
    if (lines.length == 1) return head;
    return '$head +${lines.length - 1} more';
  }

  /// Approximate margin % of revenue when lines have qty + selling_price.
  static double? _entryAvgMarginPct(Map<String, dynamic> e) {
    final lines = e['lines'];
    if (lines is! List) return null;
    var profit = 0.0;
    var rev = 0.0;
    for (final li in lines) {
      if (li is! Map) continue;
      final p = (li['profit'] as num?)?.toDouble();
      final q = (li['qty'] as num?)?.toDouble() ?? 0;
      final sp = (li['selling_price'] as num?)?.toDouble();
      if (p != null) profit += p;
      if (sp != null && q > 0) rev += q * sp;
    }
    if (rev <= 0) return null;
    return (profit / rev) * 100;
  }

  static Color? _marginStripeColor(Map<String, dynamic> e) {
    final m = _entryAvgMarginPct(e);
    if (m == null) return null;
    if (m >= 10) return const Color(0xFF2ECC71);
    if (m >= 5) return const Color(0xFFF0A500);
    return const Color(0xFFE74C3C);
  }

  static String _dateGroupLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (day.isAfter(today.subtract(const Duration(days: 7)))) return 'This week';
    return DateFormat.yMMMd().format(day);
  }

  static double _entryProfit(Map<String, dynamic> e) {
    final lines = e['lines'];
    if (lines is! List) return 0;
    var profit = 0.0;
    for (final li in lines) {
      if (li is! Map) continue;
      final p = (li['profit'] as num?)?.toDouble();
      if (p != null) profit += p;
    }
    return profit;
  }

  static ({double? buy, double? sell, String unit}) _entryBuySell(
      Map<String, dynamic> e) {
    final lines = e['lines'];
    if (lines is! List || lines.isEmpty) return (buy: null, sell: null, unit: 'unit');
    var buyTotal = 0.0;
    var buyQty = 0.0;
    var sellTotal = 0.0;
    var sellQty = 0.0;
    var unit = 'unit';
    for (final li in lines) {
      if (li is! Map) continue;
      final q = (li['qty'] as num?)?.toDouble() ?? 0;
      final u = li['unit']?.toString();
      if (u != null && u.isNotEmpty) unit = u;
      final b = ((li['landing_cost'] as num?) ?? (li['buy_price'] as num?))
          ?.toDouble();
      final s = (li['selling_price'] as num?)?.toDouble();
      if (b != null && q > 0) {
        buyTotal += q * b;
        buyQty += q;
      }
      if (s != null && q > 0) {
        sellTotal += q * s;
        sellQty += q;
      }
    }
    final buyAvg = buyQty > 0 ? buyTotal / buyQty : null;
    final sellAvg = sellQty > 0 ? sellTotal / sellQty : null;
    return (buy: buyAvg, sell: sellAvg, unit: unit);
  }

  static ({String label, Color color}) _insightTag(Map<String, dynamic> e) {
    final m = _entryAvgMarginPct(e);
    if (m == null) {
      return (label: 'No sell price', color: const Color(0xFF64748B));
    }
    if (m >= 12) return (label: 'Best deal', color: const Color(0xFF16A34A));
    if (m < 0) return (label: 'High price', color: const Color(0xFFDC2626));
    if (m < 5) return (label: 'Low margin', color: const Color(0xFFF59E0B));
    return (label: 'Stable', color: const Color(0xFF0EA5E9));
  }

  Future<void> _showFiltersSheet(BuildContext context, WidgetRef ref) async {
    final from = ref.read(entryListFromProvider);
    final to = ref.read(entryListToProvider);
    final sup = ref.read(entryListSupplierIdProvider);
    final suppliersAsync = ref.read(suppliersListProvider);
    final supplierList = suppliersAsync.valueOrNull ?? [];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) {
        DateTime? nf = from;
        DateTime? nt = to;
        String? ns = sup;
        return StatefulBuilder(
          builder: (context, setModal) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Filters',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('From date'),
                    subtitle: Text(
                        nf == null ? 'Any' : DateFormat.yMMMd().format(nf!)),
                    trailing: const Icon(Icons.calendar_today_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: nf ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setModal(() => nf = picked);
                    },
                  ),
                  ListTile(
                    title: const Text('To date'),
                    subtitle: Text(
                        nt == null ? 'Any' : DateFormat.yMMMd().format(nt!)),
                    trailing: const Icon(Icons.calendar_today_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: nt ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setModal(() => nt = picked);
                    },
                  ),
                  DropdownButtonFormField<String?>(
                    key: ValueKey(ns ?? '∅'),
                    initialValue: ns,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Any supplier')),
                      ...supplierList.map(
                        (s) => DropdownMenuItem<String?>(
                          value: s['id']?.toString(),
                          child: Text(s['name']?.toString() ?? ''),
                        ),
                      ),
                    ],
                    onChanged: (v) => setModal(() => ns = v),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setModal(() {
                            nf = null;
                            nt = null;
                            ns = null;
                          });
                        },
                        child: const Text('Clear'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () {
                          ref.read(entryListFromProvider.notifier).state = nf;
                          ref.read(entryListToProvider.notifier).state = nt;
                          ref.read(entryListSupplierIdProvider.notifier).state =
                              ns;
                          ref.invalidate(entriesListProvider);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Apply'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _applyQuickDateRange(int days) {
    final today = DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final start = end.subtract(Duration(days: days - 1));
    ref.read(entryListFromProvider.notifier).state = start;
    ref.read(entryListToProvider.notifier).state = end;
    ref.invalidate(entriesListProvider);
  }

  void _showSearchDialog(BuildContext context, WidgetRef ref) {
    final controller =
        TextEditingController(text: ref.read(entrySearchQueryProvider));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Search by item'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Item name contains…'),
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(entrySearchQueryProvider.notifier).state = '';
              _searchCtrl.text = '';
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(entrySearchQueryProvider.notifier).state =
                  controller.text;
              _searchCtrl.text = controller.text;
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(entriesListProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);
    final brokersAsync = ref.watch(brokersListProvider);
    final supplierNames = <String, String>{};
    for (final s in suppliersAsync.valueOrNull ?? []) {
      final id = s['id']?.toString();
      final n = s['name'] as String?;
      if (id != null && n != null) supplierNames[id] = n;
    }
    final brokerNames = <String, String>{};
    for (final b in brokersAsync.valueOrNull ?? []) {
      final id = b['id']?.toString();
      final n = b['name'] as String?;
      if (id != null && n != null) brokerNames[id] = n;
    }
    final searchQ = ref.watch(entrySearchQueryProvider);
    final fFrom = ref.watch(entryListFromProvider);
    final fTo = ref.watch(entryListToProvider);
    final fSup = ref.watch(entryListSupplierIdProvider);
    final hasFilters =
        fFrom != null || fTo != null || (fSup != null && fSup.isNotEmpty);

    return Scaffold(
      appBar: AppBar(
        title: searchQ.trim().isEmpty
            ? const Text('Purchase log')
            : Text('Purchase log, "$searchQ"'),
        actions: [
          IconButton(
            tooltip: 'Suppliers & contacts',
            onPressed: () => context.go('/contacts'),
            icon: const Icon(Icons.people_alt_outlined),
          ),
          const AppSettingsAction(),
          IconButton(
            tooltip: 'Filters',
            onPressed: () => _showFiltersSheet(context, ref),
            icon: Badge(
              isLabelVisible: hasFilters,
              smallSize: 8,
              child: const Icon(Icons.filter_list_rounded),
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(entriesListProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Advanced search',
            onPressed: () => _showSearchDialog(context, ref),
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: ListenableBuilder(
              listenable: _searchCtrl,
              builder: (context, _) {
                return SearchBar(
                  focusNode: _searchFocus,
                  controller: _searchCtrl,
                  hintText: 'Fuzzy search items, supplier, notes…',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(entrySearchQueryProvider.notifier).state =
                              '';
                          setState(() {});
                        },
                      ),
                  ],
                  onChanged: (_) => _onSearchChanged(),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    label: const Text('Today'),
                    onPressed: () => _applyQuickDateRange(1),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('Last 7d'),
                    onPressed: () => _applyQuickDateRange(7),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('Last 30d'),
                    onPressed: () => _applyQuickDateRange(30),
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    label: const Text('Clear dates'),
                    onPressed: () {
                      ref.read(entryListFromProvider.notifier).state = null;
                      ref.read(entryListToProvider.notifier).state = null;
                      ref.invalidate(entriesListProvider);
                    },
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => FriendlyLoadError(
                message: 'Could not load entries',
                subtitle: _entriesLoadErrorSubtitle(),
                onRetry: () => ref.invalidate(entriesListProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return HexaEmptyState(
                    icon: Icons.receipt_long_rounded,
                    title: 'No purchases in your log yet',
                    subtitle:
                        'Add a purchase to see it here. Entries sync when you are online and signed in.',
                    primaryActionLabel: 'Add purchase',
                    onPrimaryAction: () => context.push('/purchase/new'),
                  );
                }
                final sorted = List<Map<String, dynamic>>.from(items);
                sorted.sort((a, b) {
                  final da = DateTime.tryParse(
                          a['entry_date']?.toString() ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  final db = DateTime.tryParse(
                          b['entry_date']?.toString() ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0);
                  return db.compareTo(da);
                });
                final q = searchQ.trim();
                final visible = q.isEmpty
                    ? sorted
                    : catalogFuzzyRank(
                        q,
                        sorted,
                        (e) => _entryFuzzyHaystack(e, supplierNames),
                        minScore: 38,
                        limit: 2000,
                      );
                if (visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No entries match “$q”.\n'
                        'Try a shorter phrase or check spelling.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: HexaColors.textSecondary),
                      ),
                    ),
                  );
                }
                final flat = <Object>[];
                String? lastGroup;
                for (final e in visible) {
                  final raw = e['entry_date'];
                  final dt = DateTime.tryParse(raw?.toString() ?? '');
                  final label = dt == null
                      ? 'Unknown date'
                      : _dateGroupLabel(dt);
                  if (label != lastGroup) {
                    flat.add(label);
                    lastGroup = label;
                  }
                  flat.add(e);
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(entriesListProvider);
                    await ref.read(entriesListProvider.future);
                  },
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics()),
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 88),
                    itemCount: flat.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final row = flat[i];
                      if (row is String) {
                        final cs = Theme.of(context).colorScheme;
                        return Padding(
                          padding: EdgeInsets.only(
                            top: i == 0 ? 0 : 12,
                            bottom: 4,
                          ),
                          child: Text(
                            row,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurfaceVariant,
                                  letterSpacing: 0.2,
                                ),
                          ),
                        );
                      }
                      final e = row as Map<String, dynamic>;
                      final id = e['id']?.toString();
                      final stripe = _marginStripeColor(e);
                      final supplierId = e['supplier_id']?.toString();
                      final supplier =
                          supplierId != null ? supplierNames[supplierId] : null;
                      final m = _entryAvgMarginPct(e);
                      final profit = _entryProfit(e);
                      final bs = _entryBuySell(e);
                      final tag = _insightTag(e);
                      final profitColor =
                          profit >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
                      final cs = Theme.of(context).colorScheme;
                      return Material(
                        color: Colors.white,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: id == null
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  context.push('/entry/$id');
                                },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: cs.surface,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 6,
                                  height: 44,
                                  margin: const EdgeInsets.only(top: 2),
                                  decoration: BoxDecoration(
                                    color: stripe ?? cs.outlineVariant,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _titleLine(e),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${bs.buy == null ? '—' : NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(bs.buy)}'
                                        ' → ${bs.sell == null ? '—' : NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(bs.sell)}'
                                        ' / ${bs.unit}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: HexaColors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${supplier ?? 'No supplier'} · Margin ${m == null ? '—' : '${m.toStringAsFixed(1)}%'}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: HexaColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: tag.color.withValues(alpha: 0.14),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          tag.label,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: tag.color,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      NumberFormat.currency(
                                        locale: 'en_IN',
                                        symbol: '₹',
                                        decimalDigits: 0,
                                      ).format(profit),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: profitColor,
                                      ),
                                    ),
                                    Icon(
                                      profit >= 0
                                          ? Icons.trending_up_rounded
                                          : Icons.trending_down_rounded,
                                      size: 16,
                                      color: profitColor,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
