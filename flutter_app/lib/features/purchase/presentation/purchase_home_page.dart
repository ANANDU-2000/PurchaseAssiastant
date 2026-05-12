import 'dart:async';

import 'package:flutter/cupertino.dart';
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
import '../../../core/providers/analytics_kpi_provider.dart'
    show analyticsDateRangeProvider;
import '../../../core/utils/line_display.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart'
    show invalidatePurchaseWorkspace;
import '../../../core/providers/trade_purchases_provider.dart';
import '../providers/trade_purchase_detail_provider.dart';
import '../state/purchase_local_wip_draft_provider.dart';
import '../../../core/services/purchase_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart'
    show FriendlyLoadError, kFriendlyLoadNetworkSubtitle;
import '../../../core/widgets/list_skeleton.dart';
import '../../../core/widgets/focused_search_chrome.dart';

enum _HistPeriodPreset { today, week, month, year, custom }

bool _purchaseHistSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Bold digit runs in pack summary (bags / kg counts).
List<InlineSpan> _packSummaryBoldSpans(
  String pack,
  TextStyle base,
  TextStyle boldNumbers,
) {
  final re = RegExp(r'[\d,]+(?:\.\d+)?');
  final spans = <InlineSpan>[];
  var i = 0;
  for (final m in re.allMatches(pack)) {
    if (m.start > i) {
      spans.add(TextSpan(text: pack.substring(i, m.start), style: base));
    }
    spans.add(TextSpan(text: m.group(0), style: boldNumbers));
    i = m.end;
  }
  if (i < pack.length) {
    spans.add(TextSpan(text: pack.substring(i), style: base));
  }
  if (spans.isEmpty) {
    spans.add(TextSpan(text: pack.isEmpty ? '—' : pack, style: base));
  }
  return spans;
}

Widget? _purchaseHistoryDaysChip(TradePurchase p) {
  if (p.remaining <= 1e-6) {
    return null;
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final due = p.dueDate;
  if (due == null) {
    if (p.statusEnum == PurchaseStatus.overdue) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(
          'Overdue',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            height: 1.05,
            color: Colors.red.shade900,
          ),
        ),
      );
    }
    if (p.statusEnum == PurchaseStatus.dueSoon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFFDBA74)),
        ),
        child: Text(
          'Due soon',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            height: 1.05,
            color: const Color(0xFF9A3412),
          ),
        ),
      );
    }
    return null;
  }
  final dueDay = DateTime(due.year, due.month, due.day);
  final diff = dueDay.difference(today).inDays;
  final overdue = diff < 0 || p.statusEnum == PurchaseStatus.overdue;
  final String label;
  if (overdue) {
    label = diff < 0 ? '${-diff}d overdue' : 'Due today';
  } else if (diff == 0) {
    label = 'Due today';
  } else {
    label = 'Due in ${diff}d';
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    decoration: BoxDecoration(
      color: overdue ? Colors.red.shade50 : const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
        color: overdue ? Colors.red.shade200 : const Color(0xFFFDBA74),
      ),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w900,
        height: 1.05,
        color: overdue ? Colors.red.shade900 : const Color(0xFF9A3412),
      ),
    ),
  );
}

_HistPeriodPreset _purchaseHistInferPreset(({DateTime from, DateTime to}) r) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final from = DateTime(r.from.year, r.from.month, r.from.day);
  final to = DateTime(r.to.year, r.to.month, r.to.day);
  if (_purchaseHistSameDay(from, today) && _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.today;
  }
  if (_purchaseHistSameDay(from, today.subtract(const Duration(days: 6))) &&
      _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.week;
  }
  if (_purchaseHistSameDay(from, today.subtract(const Duration(days: 29))) &&
      _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.month;
  }
  if (_purchaseHistSameDay(from, DateTime(today.year, 1, 1)) &&
      _purchaseHistSameDay(to, today)) {
    return _HistPeriodPreset.year;
  }
  return _HistPeriodPreset.custom;
}

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

String _compactInrLakh(num n) {
  if (n >= 1e7) return '₹${(n / 1e7).toStringAsFixed(1)}Cr';
  if (n >= 1e5) return '₹${(n / 1e5).toStringAsFixed(1)}L';
  if (n >= 1e3) return '₹${(n / 1e3).toStringAsFixed(1)}k';
  return _inr(n);
}

/// [GoRouterState] `filter=` values that map to primary chips (`all` canonical).
const _routePrimaryPurchaseFilters = {
  'all',
  'draft',
  'due',
  'paid',
  'due_soon',
  'pending_delivery',
};

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
    b.write(' ');
    b.write(l.itemName.replaceAll(RegExp(r'[\s_\-]'), '').toLowerCase());
    if (l.itemCode != null && l.itemCode!.trim().isNotEmpty) {
      b.write(' ');
      b.write(l.itemCode);
    }
  }
  b.write(' ');
  b.write(p.itemsSummary);
  return b.toString();
}

String _historyPaymentChipLabel(PurchaseStatus st) {
  switch (st) {
    case PurchaseStatus.paid:
      return 'Paid';
    case PurchaseStatus.overdue:
      return 'Overdue';
    case PurchaseStatus.draft:
      return 'Draft';
    case PurchaseStatus.dueSoon:
      return 'Due soon';
    case PurchaseStatus.partiallyPaid:
      return 'Partial';
    default:
      return 'Pending';
  }
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

bool _purchaseHistoryMatchesDuePrimary(TradePurchase p) {
  final st = p.statusEnum;
  if (st == PurchaseStatus.paid ||
      st == PurchaseStatus.draft ||
      st == PurchaseStatus.cancelled ||
      st == PurchaseStatus.deleted) {
    return false;
  }
  if (st == PurchaseStatus.overdue || st == PurchaseStatus.dueSoon) {
    return true;
  }
  if (p.remaining > 1e-6 &&
      (st == PurchaseStatus.confirmed ||
          st == PurchaseStatus.partiallyPaid ||
          st == PurchaseStatus.saved)) {
    return true;
  }
  return false;
}

void _purchaseHistorySortPurchases(List<TradePurchase> list, bool newestFirst) {
  list.sort((a, b) {
    if (newestFirst) {
      final c = b.purchaseDate.compareTo(a.purchaseDate);
      if (c != 0) return c;
      return b.humanId.compareTo(a.humanId);
    }
    final c = a.purchaseDate.compareTo(b.purchaseDate);
    if (c != 0) return c;
    return a.humanId.compareTo(b.humanId);
  });
}

/// Shared filter + sort pipeline for Purchase History (main screen + fullscreen search).
List<TradePurchase> purchaseHistoryVisibleSortedForRef(
  WidgetRef ref,
  List<TradePurchase> items,
  String searchQ, {
  Set<String> pendingDeleteIds = const {},
}) {
  var v = items;
  final primary = ref.read(purchaseHistoryPrimaryFilterProvider);
  if (primary == 'due') {
    v = v.where(_purchaseHistoryMatchesDuePrimary).toList();
  }
  if (primary == 'draft') {
    v = v.where((p) => p.statusEnum == PurchaseStatus.draft).toList();
  }
  if (primary == 'pending_delivery') {
    v = v
        .where(
          (p) =>
              !p.isDelivered &&
              p.statusEnum != PurchaseStatus.deleted &&
              p.statusEnum != PurchaseStatus.cancelled,
        )
        .toList();
  }
  final s = ref.read(purchaseHistorySecondaryFilterProvider);
  if (s != null) {
    v = v.where((p) {
      final st = p.statusEnum;
      switch (s) {
        case 'pending':
          return st == PurchaseStatus.confirmed;
        case 'overdue':
          return st == PurchaseStatus.overdue;
        default:
          return true;
      }
    }).toList();
  }
  final subSup =
      ref.read(purchaseHistorySupplierContainsProvider)?.trim().toLowerCase();
  final subBr =
      ref.read(purchaseHistoryBrokerContainsProvider)?.trim().toLowerCase();
  final pack = ref.read(purchaseHistoryPackKindFilterProvider);
  if (!((subSup == null || subSup.isEmpty) &&
      (subBr == null || subBr.isEmpty) &&
      (pack == null || pack.isEmpty))) {
    v = v.where((p) {
      if (subSup != null && subSup.isNotEmpty) {
        final n = (p.supplierName ?? '').toLowerCase();
        if (!n.contains(subSup)) return false;
      }
      if (subBr != null && subBr.isNotEmpty) {
        final n = (p.brokerName ?? '').toLowerCase();
        if (!n.contains(subBr)) return false;
      }
      if (pack != null && pack.isNotEmpty) {
        if (!purchaseHistoryMatchesPackKindFilter(p, pack)) return false;
      }
      return true;
    }).toList();
  }
  if (pendingDeleteIds.isNotEmpty) {
    v = v.where((p) => !pendingDeleteIds.contains(p.id)).toList();
  }
  v = _filterPurchasesBySearch(v, searchQ);
  final out = List<TradePurchase>.of(v);
  _purchaseHistorySortPurchases(
    out,
    ref.read(purchaseHistorySortNewestFirstProvider),
  );
  return out;
}

bool _showQuickDeliverIcon(TradePurchase p) {
  final st = p.statusEnum;
  if (st == PurchaseStatus.deleted || st == PurchaseStatus.cancelled) {
    return false;
  }
  return !p.isDelivered;
}

bool _showQuickPaidIcon(TradePurchase p) {
  final st = p.statusEnum;
  if (st == PurchaseStatus.deleted ||
      st == PurchaseStatus.cancelled ||
      st == PurchaseStatus.draft) {
    return false;
  }
  return st != PurchaseStatus.paid;
}

/// Purchase History — filters, search, swipe actions, multi-select.
class PurchaseHomePage extends ConsumerStatefulWidget {
  const PurchaseHomePage({super.key});

  @override
  ConsumerState<PurchaseHomePage> createState() => _PurchaseHomePageState();
}

class _PurchaseHomePageState extends ConsumerState<PurchaseHomePage> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _scroll = ScrollController();
  Timer? _debounce;
  bool _selectMode = false;
  final _selected = <String>{};
  /// Purchase IDs hidden immediately while delete API runs (rolled back on failure).
  final _pendingDeleteIds = <String>{};
  /// Rows patched until list refresh completes after mark paid/delivered.
  final Map<String, TradePurchase> _optimisticPurchasePatches = {};
  String _lastRouteFilter = '';
  _HistPeriodPreset _preset = _HistPeriodPreset.month;

  void _applyPreset(_HistPeriodPreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _HistPeriodPreset.today => (from: today, to: today),
      _HistPeriodPreset.week => (from: today.subtract(const Duration(days: 6)), to: today),
      _HistPeriodPreset.month => (from: today.subtract(const Duration(days: 29)), to: today),
      _HistPeriodPreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _HistPeriodPreset.custom => ref.read(analyticsDateRangeProvider),
    };
    setState(() => _preset = p);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: range.from, end: range.to),
    );
    if (picked == null || !mounted) return;
    ref.read(analyticsDateRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
    setState(() => _preset = _HistPeriodPreset.custom);
  }

  Future<void> _openPeriodPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('Period', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Affects History + Reports totals'),
              ),
              for (final e in const [
                (_HistPeriodPreset.today, 'Today'),
                (_HistPeriodPreset.week, 'This week'),
                (_HistPeriodPreset.month, 'This month'),
                (_HistPeriodPreset.year, 'This year'),
                (_HistPeriodPreset.custom, 'Custom range'),
              ])
                ListTile(
                  leading: Icon(
                    _preset == e.$1 ? Icons.check_circle : Icons.circle_outlined,
                  ),
                  title: Text(e.$2),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (e.$1 == _HistPeriodPreset.custom) {
                      await _pickCustomRange();
                    } else {
                      _applyPreset(e.$1);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
    _searchFocus.addListener(() => setState(() {}));
    _scroll.addListener(_onHistoryScrollNearEnd);
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
    if (f == 'pending' || f == 'overdue') {
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'all';
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = f;
    } else if (f == 'paid') {
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'paid';
    } else if (f == 'due_today' || f == 'due_soon') {
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'due';
    } else {
      ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = null;
      final primary = _routePrimaryPurchaseFilters.contains(f) ? f : 'all';
      ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = primary;
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onHistoryScrollNearEnd);
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onHistoryScrollNearEnd() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 300) return;
    final async = ref.read(tradePurchasesListProvider);
    final hasMore = async.maybeWhen(
      data: (v) => v.hasMore,
      orElse: () => false,
    );
    if (!hasMore) return;
    unawaited(ref.read(tradePurchasesListProvider.notifier).loadMore());
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
    context.go(key == 'all' ? '/purchase' : '/purchase?filter=$key');
  }

  void _selectSecondary(String key) {
    ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state = 'all';
    ref.read(purchaseHistorySecondaryFilterProvider.notifier).state = key;
    context.go('/purchase?filter=$key');
  }

  Future<void> _openMoreFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _PurchaseHistoryFiltersSheet(),
    );
  }

  List<TradePurchase> _buildVisibleSorted(
    List<TradePurchase> items,
    String searchQ,
  ) {
    return purchaseHistoryVisibleSortedForRef(
      ref,
      items,
      searchQ,
      pendingDeleteIds: _pendingDeleteIds,
    );
  }

  Future<void> _confirmDelete(BuildContext context, TradePurchase p) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text('Remove ${p.humanId}?'),
        actions: [
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Delete')),
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
      ref.invalidate(tradePurchaseDetailProvider(p.id));
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
          TextButton(onPressed: () => ctx.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => ctx.pop(true), child: const Text('Delete')),
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
        ref.invalidate(tradePurchaseDetailProvider(id));
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

  List<TradePurchase> _mergeOptimisticRows(List<TradePurchase> list) {
    if (_optimisticPurchasePatches.isEmpty) return list;
    return [
      for (final row in list) _optimisticPurchasePatches[row.id] ?? row,
    ];
  }

  Future<void> _markPaidQuick(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _optimisticPurchasePatches[p.id] = p.withOptimisticMarkedPaid();
    });
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
        setState(() => _optimisticPurchasePatches.remove(p.id));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Marked paid')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        try {
          await ref.read(tradePurchasesListProvider.future);
        } catch (_) {}
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

  Future<void> _markDeliveredQuick(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _optimisticPurchasePatches[p.id] = p.withOptimisticMarkedDelivered();
    });
    try {
      await ref.read(hexaApiProvider).markPurchaseDelivered(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            isDelivered: true,
          );
      invalidatePurchaseWorkspace(ref);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked delivered')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        try {
          await ref.read(tradePurchasesListProvider.future);
        } catch (_) {}
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
    final rows =
        ref.watch(tradePurchasesParsedProvider).whenData(_mergeOptimisticRows);
    final primary = ref.watch(purchaseHistoryPrimaryFilterProvider);
    final secondary = ref.watch(purchaseHistorySecondaryFilterProvider);
    final alerts = ref.watch(purchaseAlertsProvider);
    final monthStats = ref.watch(purchaseHistoryMonthStatsProvider);
    final range = ref.watch(analyticsDateRangeProvider);
    final inferred = _purchaseHistInferPreset(range);
    if (inferred != _preset && inferred != _HistPeriodPreset.custom) {
      _preset = inferred;
    }
    final hasAdv =
        (ref.watch(purchaseHistorySupplierContainsProvider)?.trim().isNotEmpty ??
            false) ||
            (ref.watch(purchaseHistoryBrokerContainsProvider)?.trim().isNotEmpty ??
                false) ||
            (ref.watch(purchaseHistoryPackKindFilterProvider)?.isNotEmpty ??
                false) ||
            ref.watch(purchaseHistoryDateFromProvider) != null ||
            ref.watch(purchaseHistoryDateToProvider) != null;
    ref.watch(purchaseHistorySortNewestFirstProvider);
    final searchQ = ref.watch(purchaseHistorySearchProvider);
    final localWip = ref.watch(purchaseLocalWipDraftForHistoryProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: _selectMode ? 'Cancel selection' : 'Home',
          icon: Icon(_selectMode ? Icons.close_rounded : Icons.home_outlined),
          onPressed: () {
            if (_selectMode) {
              setState(() {
                _selectMode = false;
                _selected.clear();
              });
            } else {
              context.go('/home');
            }
          },
        ),
        backgroundColor: HexaColors.brandBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: _selectMode
            ? Text('${_selected.length} selected',
                style: const TextStyle(fontWeight: FontWeight.w800))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Purchase History',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: HexaColors.brandPrimary)),
                  Text(
                    '${DateFormat('d MMM').format(range.from)} → ${DateFormat('d MMM').format(range.to)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: HexaColors.neutral,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
        actions: [
          if (_selectMode) ...[
            IconButton(
              tooltip: 'Select all (filtered list)',
              onPressed: () {
                final items = rows.asData?.value;
                if (items == null) return;
                final v = _buildVisibleSorted(
                  items,
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
                final v = _buildVisibleSorted(
                  items,
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
            IconButton(
              tooltip: 'Filter by period',
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: () => unawaited(_openPeriodPicker()),
            ),
            IconButton(
              tooltip: 'More filters',
              icon: Badge(
                isLabelVisible: hasAdv,
                child: const Icon(Icons.filter_list_rounded),
              ),
              onPressed: () => unawaited(_openMoreFilters()),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'refresh',
                  child: ListTile(
                    leading: Icon(Icons.refresh_rounded),
                    title: Text('Refresh'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
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
                if (v == 'refresh') {
                  invalidatePurchaseWorkspace(ref);
                } else if (v == 'select') {
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
                label: const Text('New purchase'),
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
                message: 'Showing saved purchases — reconnecting…',
                subtitle: kFriendlyLoadNetworkSubtitle,
              ),
              data: (List<TradePurchase> items) {
                final visible = _buildVisibleSorted(items, searchQ);
                final showLocalWipRow = localWip != null &&
                    !_selectMode &&
                    (primary == 'draft' || primary == 'all');
                final searchActive = _searchFocus.hasFocus ||
                    _searchCtrl.text.trim().isNotEmpty;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              focusNode: _searchFocus,
                              decoration: const InputDecoration(
                                hintText:
                                    'Search supplier, PUR ID, items, broker…',
                                isDense: true,
                                filled: true,
                                fillColor: Colors.white,
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                ),
                                prefixIcon:
                                    Icon(Icons.search_rounded, size: 22),
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Full-screen search',
                            onPressed: () {
                              Navigator.of(context)
                                  .push<void>(
                                MaterialPageRoute<void>(
                                  fullscreenDialog: true,
                                  builder: (ctx) =>
                                      _PurchaseHistoryFullscreenSearchPage(
                                    initialSearchText:
                                        ref.read(purchaseHistorySearchProvider),
                                  ),
                                ),
                              )
                                  .then((_) {
                                if (!mounted) return;
                                _searchCtrl.text =
                                    ref.read(purchaseHistorySearchProvider);
                              });
                            },
                            icon: const Icon(Icons.open_in_full_rounded),
                          ),
                          IconButton.filledTonal(
                            tooltip: 'Filters & sort',
                            onPressed: _openMoreFilters,
                            icon: const Icon(Icons.tune_rounded),
                          ),
                        ],
                      ),
                    ),
                    CollapsibleSearchChrome(
                      searchActive: searchActive,
                      chrome: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 2),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _HistMetricPill(
                                    label: switch (_preset) {
                                      _HistPeriodPreset.today => 'Today',
                                      _HistPeriodPreset.week => 'Week',
                                      _HistPeriodPreset.month => 'Month',
                                      _HistPeriodPreset.year => 'Year',
                                      _HistPeriodPreset.custom => 'Custom',
                                    },
                                    onTap: _openPeriodPicker,
                                  ),
                                  const SizedBox(width: 6),
                                  _HistMetricPill(
                                    label: '${alerts['dueSoon'] ?? 0} Due',
                                    onTap: () => _selectPrimary('due'),
                                  ),
                                  const SizedBox(width: 6),
                                  _HistMetricPill(
                                    label: '${monthStats.purchaseCount} Purch',
                                  ),
                                  const SizedBox(width: 6),
                                  _HistMetricPill(
                                    label: monthStats.purchaseCount == 0 &&
                                            monthStats.totalInr < 1e-6
                                        ? '₹0 Mo'
                                        : '${_compactInrLakh(monthStats.totalInr)} Mo',
                                  ),
                                  const SizedBox(width: 6),
                                  _HistMetricPill(
                                    label:
                                        '${alerts['overdue'] ?? 0} Overdue',
                                    onTap: () => _selectSecondary('overdue'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
                            child: Material(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      monthStats.purchaseCount == 0 &&
                                              monthStats.totalInr < 1e-6
                                          ? 'No purchases in this period'
                                          : _compactInrLakh(monthStats.totalInr),
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w900,
                                        color: Color(0xFF0F172A),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatPurchaseHistoryMonthPackLine(
                                          monthStats),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF7C2D12),
                                        height: 1.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        children: [
                          for (final e in const [
                            ('all', 'All'),
                            ('due', 'Due'),
                            ('paid', 'Paid'),
                            ('draft', 'Draft'),
                            ('pending_delivery', '🚚 Awaiting'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(
                                  e.$2,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                selected:
                                    secondary == null && primary == e.$1,
                                onSelected: (_) => _selectPrimary(e.$1),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (secondary != null || hasAdv)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (secondary != null)
                              ActionChip(
                                label: Text(
                                  'Status: $secondary · Clear',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => _selectPrimary('all'),
                              ),
                            if (hasAdv)
                              ActionChip(
                                label: const Text(
                                  'Clear advanced filters',
                                  style: TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  ref
                                      .read(
                                        purchaseHistorySupplierContainsProvider
                                            .notifier,
                                      )
                                      .state = null;
                                  ref
                                      .read(
                                        purchaseHistoryBrokerContainsProvider
                                            .notifier,
                                      )
                                      .state = null;
                                  ref
                                      .read(
                                        purchaseHistoryPackKindFilterProvider
                                            .notifier,
                                      )
                                      .state = null;
                                  ref
                                      .read(
                                        purchaseHistoryDateFromProvider
                                            .notifier,
                                      )
                                      .state = null;
                                  ref
                                      .read(
                                        purchaseHistoryDateToProvider.notifier,
                                      )
                                      .state = null;
                                },
                              ),
                          ],
                        ),
                      ),
                    if (visible.isNotEmpty &&
                        (items.length != visible.length ||
                            items.length >= kTradePurchasesHistoryFetchLimit))
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        child: Text(
                          items.length >= kTradePurchasesHistoryFetchLimit
                              ? 'Showing latest $kTradePurchasesHistoryFetchLimit · ${visible.length} match'
                              : '${visible.length} of ${items.length}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
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
                                12 + MediaQuery.viewPaddingOf(context).bottom,
                              ),
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
                                  serial: idx + 1,
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
                                  onMarkDelivered: () => _markDeliveredQuick(p),
                                  onDelete: () => _confirmDelete(context, p),
                                  onShare: () async {
                                    try {
                                      final biz = ref.read(invoiceBusinessProfileProvider);
                                      await sharePurchasePdf(p, biz);
                                      invalidatePurchaseWorkspace(ref);
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

class _HistMetricPill extends StatelessWidget {
  const _HistMetricPill({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: HexaColors.brandBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
      ),
    );
    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }
}

class _PurchaseHistoryFiltersSheet extends ConsumerStatefulWidget {
  const _PurchaseHistoryFiltersSheet();

  @override
  ConsumerState<_PurchaseHistoryFiltersSheet> createState() =>
      _PurchaseHistoryFiltersSheetState();
}

class _PurchaseHistoryFiltersSheetState
    extends ConsumerState<_PurchaseHistoryFiltersSheet> {
  late final TextEditingController _supplier;
  late final TextEditingController _broker;

  @override
  void initState() {
    super.initState();
    _supplier = TextEditingController(
      text: ref.read(purchaseHistorySupplierContainsProvider) ?? '',
    );
    _broker = TextEditingController(
      text: ref.read(purchaseHistoryBrokerContainsProvider) ?? '',
    );
  }

  @override
  void dispose() {
    _supplier.dispose();
    _broker.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isFrom) async {
    final cur = isFrom
        ? ref.read(purchaseHistoryDateFromProvider)
        : ref.read(purchaseHistoryDateToProvider);
    final now = DateTime.now();

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      var picked = cur ?? now;
      final ok = await showCupertinoModalPopup<bool>(
        context: context,
        builder: (ctx) => Material(
          color: Colors.transparent,
          child: SafeArea(
            top: false,
            child: Container(
              height: 320,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CupertinoButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      CupertinoButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: picked,
                      minimumDate: DateTime(now.year - 5, 1, 1),
                      maximumDate: DateTime(now.year + 1, 12, 31),
                      onDateTimeChanged: (d) => picked = d,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      if (ok != true || !mounted) return;
      final d = DateTime(picked.year, picked.month, picked.day);
      if (isFrom) {
        ref.read(purchaseHistoryDateFromProvider.notifier).state = d;
      } else {
        ref.read(purchaseHistoryDateToProvider.notifier).state = d;
      }
      return;
    }

    final d = await showDatePicker(
      context: context,
      initialDate: cur ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (d == null || !mounted) return;
    if (isFrom) {
      ref.read(purchaseHistoryDateFromProvider.notifier).state = d;
    } else {
      ref.read(purchaseHistoryDateToProvider.notifier).state = d;
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd MMM yyyy');
    final pack = ref.watch(purchaseHistoryPackKindFilterProvider);
    final newest = ref.watch(purchaseHistorySortNewestFirstProvider);
    final dateFrom = ref.watch(purchaseHistoryDateFromProvider);
    final dateTo = ref.watch(purchaseHistoryDateToProvider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
          left: 16,
          right: 16,
          top: 4,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Filters & sort',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Latest first'),
                value: newest,
                onChanged: (v) {
                  ref.read(purchaseHistorySortNewestFirstProvider.notifier).state =
                      v;
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hourglass_top_rounded),
                title: const Text('Pending (confirmed)'),
                onTap: () {
                  ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state =
                      'all';
                  ref.read(purchaseHistorySecondaryFilterProvider.notifier).state =
                      'pending';
                  context.go('/purchase?filter=pending');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payments_rounded),
                title: const Text('Paid (server filter)'),
                onTap: () {
                  ref.read(purchaseHistorySecondaryFilterProvider.notifier).state =
                      null;
                  ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state =
                      'paid';
                  context.go('/purchase?filter=paid');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_rounded),
                title: const Text('Overdue'),
                onTap: () {
                  ref.read(purchaseHistoryPrimaryFilterProvider.notifier).state =
                      'all';
                  ref.read(purchaseHistorySecondaryFilterProvider.notifier).state =
                      'overdue';
                  context.go('/purchase?filter=overdue');
                  Navigator.pop(context);
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Purchase date from'),
                subtitle: Text(dateFrom != null ? df.format(dateFrom) : 'Any'),
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    ref.read(purchaseHistoryDateFromProvider.notifier).state =
                        null;
                  },
                ),
                onTap: () => _pickDate(true),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Purchase date to'),
                subtitle: Text(dateTo != null ? df.format(dateTo) : 'Any'),
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    ref.read(purchaseHistoryDateToProvider.notifier).state = null;
                  },
                ),
                onTap: () => _pickDate(false),
              ),
              DropdownButtonFormField<String?>(
                key: ValueKey<String?>(pack),
                initialValue: pack,
                decoration: const InputDecoration(
                  labelText: 'Package type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Any')),
                  DropdownMenuItem(value: 'bag', child: Text('Bag only')),
                  DropdownMenuItem(value: 'box', child: Text('Box only')),
                  DropdownMenuItem(value: 'tin', child: Text('Tin only')),
                  DropdownMenuItem(value: 'mixed', child: Text('Mixed')),
                ],
                onChanged: (v) {
                  ref.read(purchaseHistoryPackKindFilterProvider.notifier).state =
                      v;
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _supplier,
                decoration: const InputDecoration(
                  labelText: 'Supplier name contains',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _broker,
                decoration: const InputDecoration(
                  labelText: 'Broker name contains',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  ref
                          .read(purchaseHistorySupplierContainsProvider.notifier)
                          .state =
                      _supplier.text.trim().isEmpty ? null : _supplier.text.trim();
                  ref.read(purchaseHistoryBrokerContainsProvider.notifier).state =
                      _broker.text.trim().isEmpty ? null : _broker.text.trim();
                  Navigator.pop(context);
                },
                child: const Text('Apply name filters'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _supplier.clear();
                  _broker.clear();
                  ref.read(purchaseHistorySupplierContainsProvider.notifier).state =
                      null;
                  ref.read(purchaseHistoryBrokerContainsProvider.notifier).state =
                      null;
                  ref.read(purchaseHistoryPackKindFilterProvider.notifier).state =
                      null;
                  ref.read(purchaseHistoryDateFromProvider.notifier).state = null;
                  ref.read(purchaseHistoryDateToProvider.notifier).state = null;
                },
                child: const Text('Clear advanced filters'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
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

class _PurchaseHistoryFullscreenSearchPage extends ConsumerStatefulWidget {
  const _PurchaseHistoryFullscreenSearchPage({
    required this.initialSearchText,
  });

  final String initialSearchText;

  @override
  ConsumerState<_PurchaseHistoryFullscreenSearchPage> createState() =>
      _PurchaseHistoryFullscreenSearchPageState();
}

class _PurchaseHistoryFullscreenSearchPageState
    extends ConsumerState<_PurchaseHistoryFullscreenSearchPage> {
  late final TextEditingController _c;
  final Map<String, TradePurchase> _optimisticPurchasePatches = {};
  _HistPeriodPreset _preset = _HistPeriodPreset.month;

  List<TradePurchase> _mergeOptimisticRows(List<TradePurchase> list) {
    if (_optimisticPurchasePatches.isEmpty) return list;
    return [
      for (final row in list) _optimisticPurchasePatches[row.id] ?? row,
    ];
  }

  void _applyPreset(_HistPeriodPreset p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    ref.read(analyticsDateRangeProvider.notifier).state = switch (p) {
      _HistPeriodPreset.today => (from: today, to: today),
      _HistPeriodPreset.week =>
        (from: today.subtract(const Duration(days: 6)), to: today),
      _HistPeriodPreset.month =>
        (from: today.subtract(const Duration(days: 29)), to: today),
      _HistPeriodPreset.year => (from: DateTime(n.year, 1, 1), to: today),
      _HistPeriodPreset.custom => ref.read(analyticsDateRangeProvider),
    };
    setState(() => _preset = p);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = ref.read(analyticsDateRangeProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: range.from, end: range.to),
    );
    if (picked == null || !mounted) return;
    ref.read(analyticsDateRangeProvider.notifier).state =
        (from: picked.start, to: picked.end);
    setState(() => _preset = _HistPeriodPreset.custom);
  }

  Future<void> _openPeriodPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title:
                    Text('Period', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Affects History + Reports totals'),
              ),
              for (final e in const [
                (_HistPeriodPreset.today, 'Today'),
                (_HistPeriodPreset.week, 'This week'),
                (_HistPeriodPreset.month, 'This month'),
                (_HistPeriodPreset.year, 'This year'),
                (_HistPeriodPreset.custom, 'Custom range'),
              ])
                ListTile(
                  leading: Icon(
                    _preset == e.$1 ? Icons.check_circle : Icons.circle_outlined,
                  ),
                  title: Text(e.$2),
                  onTap: () async {
                    Navigator.pop(ctx);
                    if (e.$1 == _HistPeriodPreset.custom) {
                      await _pickCustomRange();
                    } else {
                      _applyPreset(e.$1);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMoreFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _PurchaseHistoryFiltersSheet(),
    );
  }

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.initialSearchText);
    _c.addListener(() {
      ref.read(purchaseHistorySearchProvider.notifier).state = _c.text.trim();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(purchaseHistorySearchProvider.notifier).state =
          widget.initialSearchText.trim();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _markPaid(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _optimisticPurchasePatches[p.id] = p.withOptimisticMarkedPaid();
    });
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
        setState(() => _optimisticPurchasePatches.remove(p.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked paid')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        try {
          await ref.read(tradePurchasesListProvider.future);
        } catch (_) {}
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

  Future<void> _markDelivered(TradePurchase p) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _optimisticPurchasePatches[p.id] = p.withOptimisticMarkedDelivered();
    });
    try {
      await ref.read(hexaApiProvider).markPurchaseDelivered(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
            isDelivered: true,
          );
      invalidatePurchaseWorkspace(ref);
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked delivered')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticPurchasePatches.remove(p.id));
        try {
          await ref.read(tradePurchasesListProvider.future);
        } catch (_) {}
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

  Future<void> _confirmDelete(BuildContext ctx, TradePurchase p) async {
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Delete purchase?'),
        content: Text('Remove ${p.humanId}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      invalidatePurchaseWorkspace(ref);
      ref.invalidate(tradePurchaseDetailProvider(p.id));
      try {
        await ref.read(tradePurchasesListProvider.future);
      } catch (_) {}
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Deleted')),
        );
      }
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
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

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(analyticsDateRangeProvider);
    final inferred = _purchaseHistInferPreset(range);
    if (inferred != _preset && inferred != _HistPeriodPreset.custom) {
      _preset = inferred;
    }
    final hasAdv =
        (ref.watch(purchaseHistorySupplierContainsProvider)?.trim().isNotEmpty ??
            false) ||
            (ref.watch(purchaseHistoryBrokerContainsProvider)?.trim().isNotEmpty ??
                false) ||
            (ref.watch(purchaseHistoryPackKindFilterProvider)?.isNotEmpty ??
                false) ||
            ref.watch(purchaseHistoryDateFromProvider) != null ||
            ref.watch(purchaseHistoryDateToProvider) != null;
    final rows =
        ref.watch(tradePurchasesParsedProvider).whenData(_mergeOptimisticRows);
    final searchQ = ref.watch(purchaseHistorySearchProvider);
    return FullscreenSearchShell(
      title: 'Search purchases',
      actions: [
        IconButton(
          tooltip: 'Filter by period',
          icon: const Icon(Icons.calendar_today_outlined),
          onPressed: () => unawaited(_openPeriodPicker()),
        ),
        IconButton(
          tooltip: 'More filters',
          icon: Badge(
            isLabelVisible: hasAdv,
            child: const Icon(Icons.filter_list_rounded),
          ),
          onPressed: () => unawaited(_openMoreFilters()),
        ),
      ],
      searchField: TextField(
        controller: _c,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search supplier, PUR ID, items, broker…',
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          prefixIcon: Icon(Icons.search_rounded, size: 22),
          contentPadding: EdgeInsets.symmetric(vertical: 10),
        ),
      ),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load purchases.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
        data: (items) {
          final visible = purchaseHistoryVisibleSortedForRef(
            ref,
            items,
            searchQ,
            pendingDeleteIds: const {},
          );
          if (visible.isEmpty) {
            return Center(
              child: Text(
                searchQ.trim().isEmpty
                    ? 'No purchases in this view.'
                    : 'No matches.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          return ListView.separated(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              12 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (ctx, i) {
              final p = visible[i];
              return _PurchaseRow(
                p: p,
                serial: i + 1,
                selectMode: false,
                selected: false,
                onLongPress: () {},
                onTap: () => context.push('/purchase/detail/${p.id}'),
                onEdit: () => context.push('/purchase/edit/${p.id}'),
                onMarkPaid: () => _markPaid(p),
                onMarkDelivered: () => _markDelivered(p),
                onDelete: () => _confirmDelete(ctx, p),
                onShare: () async {
                  try {
                    final biz = ref.read(invoiceBusinessProfileProvider);
                    await sharePurchasePdf(p, biz);
                    invalidatePurchaseWorkspace(ref);
                  } catch (_) {}
                },
              );
            },
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
    required this.onMarkDelivered,
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
  final VoidCallback onMarkDelivered;
  final VoidCallback onDelete;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final st = p.statusEnum;
    final supp = p.supplierName ?? p.supplierId?.toString() ?? '—';
    final df = DateFormat('d MMM yyyy');
    final headline = purchaseHistoryItemHeadline(p);
    final pack = purchaseHistoryPackSummary(p);
    final daysChip = _purchaseHistoryDaysChip(p);

    final card = Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? HexaColors.brandPrimary : HexaColors.brandBorder,
                width: selected ? 2 : 1),
          ),
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8, top: 1),
                child: Text(
                  '$serial.',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: HexaColors.neutral,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HexaDsType.purchaseQtyUnit.copyWith(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF0F172A),
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF0F172A),
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              children: _packSummaryBoldSpans(
                                pack,
                                const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: HexaColors.neutral,
                                  height: 1.15,
                                ),
                                const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (daysChip != null) ...[
                          const SizedBox(width: 6),
                          daysChip,
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${p.humanId} • ${df.format(p.purchaseDate)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: HexaColors.neutral,
                        height: 1.1,
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
                      fontSize: 15,
                      letterSpacing: -0.3,
                      height: 1.1,
                    ),
                  ),
                  if (!selectMode &&
                      (_showQuickDeliverIcon(p) || _showQuickPaidIcon(p))) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_showQuickDeliverIcon(p))
                          IconButton(
                            tooltip: 'Mark delivered',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 30,
                              minHeight: 30,
                            ),
                            style: IconButton.styleFrom(
                              foregroundColor: Colors.orange.shade800,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(
                              Icons.local_shipping_outlined,
                              size: 18,
                            ),
                            onPressed: onMarkDelivered,
                          ),
                        if (_showQuickPaidIcon(p))
                          IconButton(
                            tooltip: 'Mark paid',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 30,
                              minHeight: 30,
                            ),
                            style: IconButton.styleFrom(
                              foregroundColor: HexaColors.brandAccent,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(
                              Icons.payments_outlined,
                              size: 18,
                            ),
                            onPressed: onMarkPaid,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 1),
                  if (!p.isDelivered &&
                      p.statusEnum != PurchaseStatus.deleted &&
                      p.statusEnum != PurchaseStatus.cancelled)
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Text(
                        '🚚 Pending',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else if (p.isDelivered)
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '✅ Received',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green.shade800,
                        ),
                      ),
                    ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: st.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _historyPaymentChipLabel(st),
        style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700, height: 1.05, color: st.color),
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
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: HexaColors.brandPrimary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            const Text('No purchases yet',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: HexaColors.brandPrimary)),
            const SizedBox(height: 8),
            Text(
              'Create a purchase to see it here. Search and filters apply once you have bills on file.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAdd, child: const Text('New purchase')),
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
