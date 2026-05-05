import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/search/catalog_fuzzy.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/calc_engine.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidatePurchaseWorkspace;
import '../../../core/providers/trade_purchases_provider.dart';
import '../state/purchase_local_wip_draft_provider.dart';
import 'widgets/due_soon_banner.dart';
import '../../../core/services/purchase_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

/// [GoRouterState] `filter=` values that map to primary chips (`all` canonical).
const _routePrimaryPurchaseFilters = {'all', 'draft', 'due_soon'};

String _purchaseSearchHaystack(TradePurchase p) {
  final df = DateFormat('dd MMM yyyy');
  final b = StringBuffer()
    ..write(p.id)
    ..write(' ')
    ..write(p.humanId)
    ..write(' ')
    ..write(p.invoiceNumber ?? '')
    ..write(' ')
    ..write(df.format(p.purchaseDate))
    ..write(' ')
    ..write(p.supplierName ?? '')
    ..write(' ')
    ..write(p.brokerName ?? '');
  for (final l in p.lines) {
    b.write(' ');
    b.write(l.itemName);
  }
  b.write(' ');
  b.write(p.itemsSummary);
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

/// Purchase History — filters, search, swipe actions, multi-select.
class PurchaseHomePage extends ConsumerStatefulWidget {
  const PurchaseHomePage({super.key});

  @override
  ConsumerState<PurchaseHomePage> createState() => _PurchaseHomePageState();
}

class _PurchaseHomePageState extends ConsumerState<PurchaseHomePage> {
  final _searchCtrl = TextEditingController();
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
      final primary =
          _routePrimaryPurchaseFilters.contains(f) ? f : 'all';
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = primary;
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
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      ref.read(purchaseHistorySearchProvider.notifier).state =
          _searchCtrl.text.trim();
    });
  }

  void _selectPrimary(String key) {
    ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = key;
    ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
    ref.invalidate(purchaseHistorySearchProvider);
    context.go(key == 'all' ? '/purchase' : '/purchase?filter=$key');
  }

  void _selectSecondary(String key) {
    ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'all';
    ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = key;
    ref.invalidate(purchaseHistorySearchProvider);
    context.go('/purchase?filter=$key');
  }

  Future<void> _openMoreFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
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
      invalidatePurchaseWorkspace(ref);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (!mounted) return;
      setState(() => _pendingDeleteIds.remove(p.id));
      messenger.showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
      if (mounted) {
        setState(() => _pendingDeleteIds.remove(p.id));
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is DioException
                ? friendlyApiError(e)
                : 'Something went wrong. Please try again.',
          ),
        ),
      );
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
    invalidatePurchaseWorkspace(ref);
    try {
      await ref.read(tradePurchasesListProvider.future);
    } catch (_) {}
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
      invalidatePurchaseWorkspace(ref);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked paid')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is DioException
                  ? friendlyApiError(e)
                  : 'Something went wrong. Please try again.',
            ),
          ),
        );
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
    final localWip = ref.watch(purchaseLocalWipDraftForHistoryProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: HexaColors.brandBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: _selectMode
            ? Text('${_selected.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w800))
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
          ] else ...[
            ShellQuickRefActions(
              onRefresh: () {
                invalidatePurchaseWorkspace(ref);
              },
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'select',
                  child: ListTile(
                    leading: Icon(Icons.checklist_rtl_rounded),
                    title: Text('Select purchases'),
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
              ],
              onSelected: (v) {
                if (v == 'select') {
                  setState(() => _selectMode = true);
                } else if (v == 'scan') {
                  context.push('/purchase/scan');
                }
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
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const ListSkeleton(),
              error: (_, __) => FriendlyLoadError(
                onRetry: () {
                  invalidatePurchaseWorkspace(ref);
                },
              ),
              data: (List<TradePurchase> items) {
                final visible = _filterPurchasesBySearch(
                  _applySecondary(_withoutPendingDeletes(items)),
                  searchQ,
                );
                final showLocalWipRow = localWip != null && !_selectMode;
                return Column(
                  children: [
                    DueSoonBanner(
                      count: dueAlert,
                      onTap: () => _selectPrimary('due_soon'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                      child: TextField(
                        controller: _searchCtrl,
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final e in const [
                            ('all', 'All'),
                            ('draft', 'Draft'),
                            ('due_soon', 'Due soon'),
                          ])
                            FilterChip(
                              label: Text(e.$2),
                              selected: secondary == null && primary == e.$1,
                              onSelected: (_) => _selectPrimary(e.$1),
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
                      child: visible.isEmpty && !showLocalWipRow
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
                                  80 + MediaQuery.of(context).padding.bottom),
                      itemCount: visible.length + (showLocalWipRow ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                              itemBuilder: (context, i) {
                                if (showLocalWipRow && i == 0) {
                                  return _LocalWipDraftHistoryRow(vm: localWip);
                                }
                                final idx = i - (showLocalWipRow ? 1 : 0);
                                final p = visible[idx];
                                return _PurchaseRow(
                                  p: p,
                                  serial: visible.length - idx,
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

class _LocalWipDraftHistoryRow extends StatelessWidget {
  const _LocalWipDraftHistoryRow({required this.vm});

  final PurchaseLocalWipDraftVm vm;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => context.pushNamed(
          'purchase_new',
          extra: <String, dynamic>{'resumeDraft': true},
        ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.7),
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Draft',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD97706),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            vm.titleLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: HexaDsType.purchaseQtyUnit.copyWith(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vm.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: HexaColors.neutral,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade600),
            ],
          ),
        ),
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

  static ({
    double kg,
    double bags,
    double boxes,
    double tins,
  }) _totals(TradePurchase p) {
    var kg = 0.0;
    var bags = 0.0;
    var boxes = 0.0;
    var tins = 0.0;
    for (final ln in p.lines) {
      final ul = ln.unit.trim().toLowerCase();
      if (unitCountsAsBagFamily(ln.unit)) bags += ln.qty;
      if (ul == 'box') boxes += ln.qty;
      if (ul == 'tin') tins += ln.qty;
      kg += ledgerTradeLineWeightKg(
        itemName: ln.itemName,
        unit: ln.unit,
        qty: ln.qty,
        catalogDefaultUnit: ln.defaultPurchaseUnit ?? ln.defaultUnit,
        catalogDefaultKgPerBag: ln.defaultKgPerBag,
        kgPerUnit: ln.kgPerUnit,
        boxMode: ln.boxMode,
        itemsPerBox: ln.itemsPerBox,
        weightPerItem: ln.weightPerItem,
        kgPerBox: ln.kgPerBox,
        weightPerTin: ln.weightPerTin,
      );
    }
    return (kg: kg, bags: bags, boxes: boxes, tins: tins);
  }

  @override
  Widget build(BuildContext context) {
    final st = p.statusEnum;
    final supp = p.supplierName ?? p.supplierId?.toString() ?? '—';
    final df = DateFormat('d MMM yyyy');
    final t = _totals(p);

    final firstLine = p.lines.isNotEmpty ? p.lines.first : null;
    final itemName = firstLine?.itemName ?? '—';
    final moreCount = p.lines.length > 1 ? ' +${p.lines.length - 1}' : '';

    // Prefer "100 bags • 5,000 kg" when we have a container count; otherwise show kg.
    final weightStr = t.bags > 1e-6
        ? formatLineQtyWeight(qty: t.bags, unit: 'bag', totalWeightKg: t.kg)
        : (t.boxes > 1e-6
            ? formatLineQtyWeight(qty: t.boxes, unit: 'box', totalWeightKg: t.kg)
            : (t.tins > 1e-6
                ? formatLineQtyWeight(qty: t.tins, unit: 'tin', totalWeightKg: t.kg)
                : formatLineQtyWeight(qty: t.kg, unit: 'kg')));

    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? HexaColors.brandPrimary : HexaColors.brandBorder,
                width: selected ? 2 : 1),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HexaDsType.purchaseQtyUnit.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$itemName$moreCount  •  $weightStr',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF0F172A),
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.humanId}  ·  ${df.format(p.purchaseDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: HexaColors.neutral,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _inr(p.totalAmount.round()),
                    style: HexaDsType.purchaseLineMoney.copyWith(
                      fontSize: 16,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  _MiniBadge(st),
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
