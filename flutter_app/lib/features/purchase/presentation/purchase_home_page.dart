import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import 'widgets/due_soon_banner.dart';
import '../../../core/services/purchase_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _purchaseFirstLineLabel(TradePurchase p) {
  if (p.lines.isEmpty) return 'No items';
  final ln = p.lines.first;
  return '${ln.itemName} · ${ln.qty} ${ln.unit}';
}

double _totalBagsOnPurchase(TradePurchase p) {
  var b = 0.0;
  for (final ln in p.lines) {
    if (ln.unit.toUpperCase().contains('BAG')) b += ln.qty;
  }
  return b;
}

String _purchaseSearchHaystack(TradePurchase p) {
  final b = StringBuffer()
    ..write(p.humanId)
    ..write(' ')
    ..write(p.supplierName ?? '')
    ..write(' ')
    ..write(p.brokerName ?? '');
  for (final l in p.lines) {
    b.write(' ');
    b.write(l.itemName);
  }
  return b.toString();
}

String _histCsvCell(String raw) {
  final s = raw.replaceAll('\r\n', ' ').replaceAll('\n', ' ').trim();
  if (s.contains(',') || s.contains('"')) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

List<TradePurchase> _filterPurchasesBySearch(
  List<TradePurchase> base,
  String searchQuery,
) {
  final sq = searchQuery.trim();
  if (sq.isEmpty) return base;
  return catalogFuzzyRank(
    sq,
    base,
    _purchaseSearchHaystack,
    minScore: sq.length <= 1 ? 8.0 : 22.0,
    limit: 400,
  );
}

String? _dueFooterLine(TradePurchase p) {
  if (p.dueDate == null || p.remaining <= 0.01 || p.statusEnum == PurchaseStatus.paid) {
    return null;
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(p.dueDate!.year, p.dueDate!.month, p.dueDate!.day);
  final days = d.difference(today).inDays;
  if (days < 0) return 'Overdue by ${-days} day(s)';
  if (days <= 3) return 'Due in $days day(s)';
  return null;
}

/// Purchase History — filters, search, swipe actions, multi-select.
class PurchaseHomePage extends ConsumerStatefulWidget {
  const PurchaseHomePage({super.key});

  @override
  ConsumerState<PurchaseHomePage> createState() => _PurchaseHomePageState();
}

class _PurchaseHomePageState extends ConsumerState<PurchaseHomePage> {
  /// Narrow layout: simplified app bar (title + search + menu).
  static const double _compactAppBarBreakpoint = 600;

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _selectMode = false;
  final _selected = <String>{};
  /// Purchase IDs hidden immediately while delete API runs (rolled back on failure).
  final _pendingDeleteIds = <String>{};
  String _lastRouteFilter = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final raw = GoRouterState.of(context).uri.queryParameters['filter'];
    final f = (raw == null || raw.isEmpty) ? 'all' : raw.toLowerCase();
    if (f == _lastRouteFilter) return;
    _lastRouteFilter = f;
    _syncFilterFromRoute();
  }

  void _syncFilterFromRoute() {
    final q = GoRouterState.of(context).uri.queryParameters['filter'];
    final f = (q == null || q.isEmpty) ? 'all' : q.toLowerCase();
    if (f == 'pending' || f == 'paid' || f == 'overdue') {
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'all';
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = f;
    } else if (f == 'due_today') {
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'due_soon';
    } else {
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = f;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      ref.read(purchaseHistorySearchProvider.notifier).state =
          _searchCtrl.text.trim();
    });
  }

  void _selectPrimary(String key) {
    ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = key;
    ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
    context.go(key == 'all' ? '/purchase' : '/purchase?filter=$key');
  }

  void _selectSecondary(String key) {
    ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'all';
    ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = key;
    context.go('/purchase?filter=$key');
  }

  void _focusHistorySearch() {
    FocusScope.of(context).requestFocus(_searchFocus);
  }

  Future<void> _openMoreFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('More filters', style: TextStyle(fontWeight: FontWeight.w800))),
            ListTile(
              leading: const Icon(Icons.hourglass_top_rounded),
              title: const Text('Pending'),
              onTap: () {
                Navigator.pop(ctx);
                _selectSecondary('pending');
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments_rounded),
              title: const Text('Paid'),
              onTap: () {
                Navigator.pop(ctx);
                _selectSecondary('paid');
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded),
              title: const Text('Overdue'),
              onTap: () {
                Navigator.pop(ctx);
                _selectSecondary('overdue');
              },
            ),
          ],
        ),
      ),
    );
  }

  List<TradePurchase> _withoutPendingDeletes(List<TradePurchase> all) {
    if (_pendingDeleteIds.isEmpty) return all;
    return all.where((p) => !_pendingDeleteIds.contains(p.id)).toList();
  }

  List<TradePurchase> _applySecondary(List<TradePurchase> all) {
    final s = ref.read(purchaseHistorySecondaryFilterProvider);
    if (s == null) return all;
    return all.where((p) {
      final st = p.statusEnum;
      switch (s) {
        case 'pending':
          return st == PurchaseStatus.confirmed;
        case 'paid':
          return st == PurchaseStatus.paid;
        case 'overdue':
          return st == PurchaseStatus.overdue;
        default:
          return true;
      }
    }).toList();
  }

  Future<void> _confirmDelete(BuildContext context, TradePurchase p) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text('Remove ${p.humanId}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    setState(() => _pendingDeleteIds.add(p.id));
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      ref.invalidate(tradePurchasesListProvider);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      invalidateBusinessAggregates(ref);
      if (!mounted) return;
      setState(() => _pendingDeleteIds.remove(p.id));
      messenger.showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (mounted) {
        setState(() => _pendingDeleteIds.remove(p.id));
      }
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _bulkDelete(BuildContext context) async {
    if (_selected.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selected.length} purchases?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final ids = _selected.toList();
    setState(() {
      for (final id in ids) {
        _pendingDeleteIds.add(id);
      }
      _selectMode = false;
      _selected.clear();
    });
    for (final id in ids) {
      try {
        await ref.read(hexaApiProvider).deleteTradePurchase(
              businessId: session.primaryBusiness.id,
              purchaseId: id,
            );
      } catch (_) {
        if (mounted) {
          setState(() => _pendingDeleteIds.remove(id));
        }
      }
    }
    ref.invalidate(tradePurchasesListProvider);
    try {
      await ref.read(tradePurchasesListProvider.future);
    } catch (_) {}
    invalidateBusinessAggregates(ref);
    if (mounted) {
      setState(() => _pendingDeleteIds.removeAll(ids));
    }
  }

  void _selectAllVisible(List<TradePurchase> visible) {
    if (visible.isEmpty) return;
    setState(() {
      _selectMode = true;
      _selected
        ..clear()
        ..addAll(visible.map((e) => e.id));
    });
  }

  Future<void> _exportSelectedCsv(List<TradePurchase> visible) async {
    if (_selected.isEmpty) return;
    final pick = visible.where((p) => _selected.contains(p.id)).toList();
    if (pick.isEmpty) return;
    final df = DateFormat('yyyy-MM-dd');
    final buf = StringBuffer()
      ..writeln('human_id,purchase_date,supplier,total_inr,remaining_inr,status');
    for (final p in pick) {
      buf.writeln(
        '${_histCsvCell(p.humanId)},${df.format(p.purchaseDate)},'
        '${_histCsvCell(p.supplierName ?? '')},${p.totalAmount.toStringAsFixed(2)},'
        '${p.remaining.toStringAsFixed(2)},${_histCsvCell(p.derivedStatus)}',
      );
    }
    await Share.share(
      buf.toString(),
      subject: 'Purchase export (${pick.length})',
    );
  }

  Future<void> _markPaidQuick(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).markPurchasePaid(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      ref.invalidate(tradePurchasesListProvider);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      invalidateBusinessAggregates(ref);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked paid')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final rows = ref.watch(tradePurchasesParsedProvider);
    final primary = ref.watch(purchaseHistoryPrimaryFilterProvider);
    final secondary = ref.watch(purchaseHistorySecondaryFilterProvider);
    final alerts = ref.watch(purchaseAlertsProvider);
    final dueAlert = (alerts['dueSoon'] ?? 0) + (alerts['overdue'] ?? 0);
    final searchQ = ref.watch(purchaseHistorySearchProvider);
    final narrow =
        MediaQuery.sizeOf(context).width < _compactAppBarBreakpoint;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: kToolbarHeight,
        titleSpacing: narrow ? 16 : null,
        actionsIconTheme: IconThemeData(
          size: narrow ? 23 : 22,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        bottom: narrow
            ? PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: HexaColors.brandBorder.withValues(alpha: 0.65),
                ),
              )
            : null,
        title: _selectMode
            ? Text('${_selected.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w800))
            : narrow
                ? Text(
                    'History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  )
                : const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Purchase History',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: HexaColors.brandPrimary)),
                      Text('All trade purchases',
                          style: TextStyle(
                              fontSize: 11,
                              color: HexaColors.neutral,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
        actions: [
          if (_selectMode) ...[
            IconButton(
              tooltip: 'Select all (filtered list)',
              onPressed: () {
                final items = rows.asData?.value;
                if (items == null) return;
                final v = _filterPurchasesBySearch(
                  _applySecondary(_withoutPendingDeletes(items)),
                  ref.read(purchaseHistorySearchProvider),
                );
                _selectAllVisible(v);
              },
              icon: const Icon(Icons.select_all_rounded),
            ),
            IconButton(
              tooltip: 'Export selected CSV',
              onPressed: () async {
                final items = rows.asData?.value;
                if (items == null) return;
                final v = _filterPurchasesBySearch(
                  _applySecondary(_withoutPendingDeletes(items)),
                  ref.read(purchaseHistorySearchProvider),
                );
                await _exportSelectedCsv(v);
              },
              icon: const Icon(Icons.ios_share_rounded),
            ),
            IconButton(
              tooltip: 'Delete',
              onPressed: () => _bulkDelete(context),
              icon: const Icon(Icons.delete_outline_rounded, color: HexaColors.loss),
            ),
            IconButton(
              tooltip: 'Cancel',
              onPressed: () => setState(() {
                _selectMode = false;
                _selected.clear();
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ] else if (narrow) ...[
            IconButton(
              tooltip: 'Search',
              onPressed: _focusHistorySearch,
              icon: const Icon(Icons.search_rounded),
            ),
            const SizedBox(width: 12),
            PopupMenuButton<String>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert_rounded),
              padding: EdgeInsets.zero,
              offset: const Offset(0, kToolbarHeight - 12),
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'new',
                  child: ListTile(
                    leading: Icon(Icons.add_rounded),
                    title: Text('New purchase'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'scan',
                  child: ListTile(
                    leading: Icon(Icons.document_scanner_outlined),
                    title: Text('Scan bill'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'filters',
                  child: ListTile(
                    leading: Icon(Icons.filter_list_rounded),
                    title: Text('More filters'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: Icon(Icons.refresh_rounded),
                    title: Text('Refresh list'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'catalog',
                  child: ListTile(
                    leading: Icon(Icons.inventory_2_outlined),
                    title: Text('Catalog'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'contacts',
                  child: ListTile(
                    leading: Icon(Icons.groups_outlined),
                    title: Text('Contacts'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'notifications',
                  child: ListTile(
                    leading: Icon(Icons.notifications_outlined),
                    title: Text('Alerts'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: ListTile(
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Settings'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const PopupMenuItem(
                  value: 'global_search',
                  child: ListTile(
                    leading: Icon(Icons.travel_explore_outlined),
                    title: Text('Global search'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (v) {
                switch (v) {
                  case 'new':
                    context.push('/purchase/new');
                  case 'scan':
                    context.push('/purchase/scan');
                  case 'filters':
                    _openMoreFilters();
                  case 'refresh':
                    ref.invalidate(tradePurchasesListProvider);
                    invalidateBusinessAggregates(ref);
                  case 'catalog':
                    context.push('/catalog');
                  case 'contacts':
                    context.push('/contacts');
                  case 'notifications':
                    context.push('/notifications');
                  case 'settings':
                    context.go('/settings');
                  case 'global_search':
                    context.push('/search');
                }
              },
            ),
            const SizedBox(width: 8),
          ] else ...[
            ShellQuickRefActions(
              onRefresh: () {
                ref.invalidate(tradePurchasesListProvider);
                invalidateBusinessAggregates(ref);
              },
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'scan',
                  child: ListTile(
                    leading: Icon(Icons.document_scanner_outlined),
                    title: Text('Scan bill'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (v) {
                if (v == 'scan') context.push('/purchase/scan');
              },
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: () => context.push('/purchase/new'),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New'),
                style: FilledButton.styleFrom(
                  backgroundColor: HexaColors.brandPrimary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 36),
                ),
              ),
            ),
          ],
        ],
      ),
      body: session == null
          ? _SignInPrompt(onTap: () => context.go('/login'))
          : rows.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: HexaColors.brandPrimary, strokeWidth: 2)),
              error: (_, __) => FriendlyLoadError(
                onRetry: () {
                  ref.invalidate(tradePurchasesListProvider);
                  invalidateBusinessAggregates(ref);
                },
              ),
              data: (List<TradePurchase> items) {
                final visible = _filterPurchasesBySearch(
                  _applySecondary(_withoutPendingDeletes(items)),
                  searchQ,
                );
                return Column(
                  children: [
                    DueSoonBanner(
                      count: dueAlert,
                      onTap: () => _selectPrimary('due_soon'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: TextField(
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        scrollPadding: const EdgeInsets.only(bottom: 120),
                        decoration: const InputDecoration(
                          hintText: 'Search supplier, purchase ID, item name…',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          for (final e in const [
                            ('all', 'All'),
                            ('draft', 'Draft'),
                            ('due_soon', 'Due soon'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(e.$2),
                                selected: secondary == null && primary == e.$1,
                                onSelected: (_) => _selectPrimary(e.$1),
                              ),
                            ),
                          IconButton.filledTonal(
                            tooltip: 'More filters',
                            onPressed: _openMoreFilters,
                            icon: const Icon(Icons.filter_list_rounded),
                          ),
                        ],
                      ),
                    ),
                    if (secondary != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: ActionChip(
                            label: Text('Filtered: $secondary · Clear'),
                            onPressed: () => _selectPrimary('all'),
                          ),
                        ),
                      ),
                    if (visible.isNotEmpty && (items.length != visible.length || items.length >= 200))
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        child: Text(
                          items.length >= 200
                              ? 'Showing latest 200 · ${visible.length} match'
                              : '${visible.length} of ${items.length}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    Expanded(
                      child: visible.isEmpty
                          ? _HistoryEmpty(onAdd: () => context.push('/purchase/new'))
                          : ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics()),
                              key: PageStorageKey<String>('hist_${primary}_${secondary ?? ''}_${ref.watch(purchaseHistorySearchProvider)}'),
                              controller: _scroll,
                              padding: EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  80 +
                                      MediaQuery.viewPaddingOf(context)
                                          .bottom),
                              itemCount: visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final p = visible[i];
                                return _PurchaseRow(
                                  p: p,
                                  serial: visible.length - i,
                                  selectMode: _selectMode,
                                  selected: _selected.contains(p.id),
                                  onLongPress: () {
                                    HapticFeedback.mediumImpact();
                                    setState(() {
                                      _selectMode = true;
                                      _selected.add(p.id);
                                    });
                                  },
                                  onTap: () {
                                    if (_selectMode) {
                                      setState(() {
                                        if (_selected.contains(p.id)) {
                                          _selected.remove(p.id);
                                        } else {
                                          _selected.add(p.id);
                                        }
                                      });
                                    } else {
                                      context.push('/purchase/detail/${p.id}');
                                    }
                                  },
                                  onEdit: () =>
                                      context.push('/purchase/edit/${p.id}'),
                                  onMarkPaid: () => _markPaidQuick(p),
                                  onDelete: () => _confirmDelete(context, p),
                                  onShare: () async {
                                    try {
                                      final biz = ref.read(invoiceBusinessProfileProvider);
                                      await sharePurchasePdf(p, biz);
                                    } catch (_) {}
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({
    required this.p,
    required this.serial,
    required this.selectMode,
    required this.selected,
    required this.onLongPress,
    required this.onTap,
    required this.onEdit,
    required this.onMarkPaid,
    required this.onDelete,
    required this.onShare,
  });

  final TradePurchase p;
  final int serial;
  final bool selectMode;
  final bool selected;
  final VoidCallback onLongPress;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onMarkPaid;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final st = p.statusEnum;
    final supp = p.supplierName ?? p.supplierId?.toString() ?? '—';
    final bags = _totalBagsOnPurchase(p);
    final bagsText = bags > 0
        ? '${(bags - bags.floor()).abs() < 1e-6 ? bags.toInt() : bags.toStringAsFixed(1)} bags'
        : '';
    final dueFoot = _dueFooterLine(p);
    final footColor = st == PurchaseStatus.overdue
        ? HexaColors.loss
        : (st == PurchaseStatus.dueSoon ? const Color(0xFFCA8A04) : HexaColors.neutral);

    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: selected ? HexaColors.brandPrimary : HexaColors.brandBorder,
                width: selected ? 2 : 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              )
            ],
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$serial',
                  style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: HexaColors.neutral),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Supplier: $supp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _purchaseFirstLineLabel(p),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: HexaColors.neutral, height: 1.2),
                    ),
                    if (bagsText.isNotEmpty)
                      Text(
                        bagsText,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.humanId,
                            style: const TextStyle(fontSize: 10, color: HexaColors.neutral),
                          ),
                        ),
                        _MiniBadge(st),
                      ],
                    ),
                    if (dueFoot != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          dueFoot,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: footColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_inr(p.totalAmount.round()),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: HexaColors.brandPrimary)),
                  Text('Rem ${_inr(p.remaining.round())}',
                      style: const TextStyle(fontSize: 10, color: HexaColors.neutral)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (selectMode) return card;

    return Slidable(
      key: ValueKey(p.id),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => onEdit(),
            backgroundColor: HexaColors.brandPrimary,
            foregroundColor: Colors.white,
            icon: Icons.edit_rounded,
            label: 'Edit',
          ),
          SlidableAction(
            onPressed: (_) => onMarkPaid(),
            backgroundColor: HexaColors.brandAccent,
            foregroundColor: Colors.white,
            icon: Icons.payments_rounded,
            label: 'Paid',
          ),
          SlidableAction(
            onPressed: (_) => onShare(),
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
            icon: Icons.share_rounded,
            label: 'Share',
          ),
          SlidableAction(
            onPressed: (_) => onDelete(),
            backgroundColor: HexaColors.loss,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline_rounded,
            label: 'Del',
          ),
        ],
      ),
      child: card,
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge(this.st);
  final PurchaseStatus st;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: st.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        st.label,
        style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: st.color),
      ),
    );
  }
}

class _HistoryEmpty extends StatelessWidget {
  const _HistoryEmpty({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No purchases match',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: HexaColors.brandPrimary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onAdd, child: const Text('Add Purchase')),
          ],
        ),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(onPressed: onTap, child: const Text('Sign In')),
    );
  }
}
