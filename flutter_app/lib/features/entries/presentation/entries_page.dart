import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/brokers_list_provider.dart';
import '../../../core/providers/entries_list_provider.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/app_settings_action.dart';
import '../../../core/widgets/friendly_load_error.dart'
    show FriendlyLoadError, kFriendlyLoadNetworkSubtitle;
import '../../../shared/widgets/hexa_empty_state.dart';
import 'entry_create_sheet.dart';

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
    ref.invalidate(entriesListProvider);
    setState(() {});
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
    return DateFormat.yMMMd().format(day);
  }

  static String _subtitle(
    Map<String, dynamic> e, {
    Map<String, String> supplierNames = const {},
    Map<String, String> brokerNames = const {},
  }) {
    final lines = e['lines'];
    final sid = e['supplier_id']?.toString();
    final brid = e['broker_id']?.toString();
    final sup = sid != null ? supplierNames[sid] : null;
    final bro = brid != null ? brokerNames[brid] : null;

    final line1 = StringBuffer();
    if (sup != null) {
      line1.write('Supplier: $sup');
    }
    if (bro != null) {
      if (line1.isNotEmpty) line1.write('  ·  ');
      line1.write('Broker: $bro');
    }

    final mid = StringBuffer();
    if (lines is List && lines.isNotEmpty) {
      final first = lines.first;
      if (first is Map) {
        final q = first['qty'];
        final u = first['unit'];
        final bp = first['buy_price'];
        if (q != null) {
          mid.write('$q ${u ?? ''}'.trim());
        }
        if (bp != null) {
          if (mid.isNotEmpty) mid.write(' · ');
          final bpv = (bp is num)
              ? bp.toDouble()
              : double.tryParse(bp.toString()) ?? 0;
          mid.write(
              'Buy ${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(bpv)}');
        }
      }
    }
    var profit = 0.0;
    if (lines is List) {
      for (final li in lines) {
        if (li is Map) {
          final p = li['profit'];
          if (p is num) profit += p.toDouble();
        }
      }
    }
    final pl = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(profit);
    final mPct = _entryAvgMarginPct(e);
    final profitBit = StringBuffer('Profit: $pl');
    if (mPct != null) {
      profitBit.write(' (${mPct.toStringAsFixed(1)}%)');
    }

    final raw = e['entry_date'];
    var dateStr = '';
    if (raw != null) {
      final dt = DateTime.tryParse(raw.toString());
      if (dt != null) {
        dateStr = DateFormat.yMMMd().format(dt);
      }
    }

    final parts = <String>[];
    if (line1.isNotEmpty) parts.add(line1.toString());
    if (mid.isNotEmpty) parts.add(mid.toString());
    parts.add(profitBit.toString());
    if (dateStr.isNotEmpty) parts.add(dateStr);
    return parts.join('\n');
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
              ref.invalidate(entriesListProvider);
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(entrySearchQueryProvider.notifier).state =
                  controller.text;
              ref.invalidate(entriesListProvider);
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
                  hintText: 'Search items, notes…',
                  leading: const Icon(Icons.search_rounded),
                  trailing: [
                    if (_searchCtrl.text.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(entrySearchQueryProvider.notifier).state =
                              '';
                          ref.invalidate(entriesListProvider);
                          setState(() {});
                        },
                      ),
                  ],
                  onChanged: (_) => _onSearchChanged(),
                );
              },
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
                    onPrimaryAction: () => showEntryCreateSheet(context),
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
                final flat = <Object>[];
                String? lastGroup;
                for (final e in sorted) {
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
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          onTap: id == null
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  context.push('/entry/$id');
                                },
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (stripe != null)
                                  Container(width: 4, color: stripe),
                                Expanded(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 8),
                                    title: Text(
                                      _titleLine(e),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    isThreeLine: true,
                                    subtitle: Text(
                                      _subtitle(
                                        e,
                                        supplierNames: supplierNames,
                                        brokerNames: brokerNames,
                                      ),
                                      style: const TextStyle(
                                        height: 1.35,
                                        fontSize: 12,
                                        color: HexaColors.textSecondary,
                                      ),
                                    ),
                                    trailing: const Icon(
                                        Icons.chevron_right_rounded),
                                  ),
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
