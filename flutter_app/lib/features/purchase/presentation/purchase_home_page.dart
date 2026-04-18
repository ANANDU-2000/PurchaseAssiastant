import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/business_profile_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/services/purchase_pdf.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

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
  String _query = '';
  bool _selectMode = false;
  final _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
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
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _query = _searchCtrl.text.trim());
    });
  }

  String _filterFromRoute() {
    final q = GoRouterState.of(context).uri.queryParameters['filter'];
    if (q == null || q.isEmpty) return 'all';
    return q.toLowerCase();
  }

  bool _matchesFilter(TradePurchase p, String f) {
    final st = p.statusEnum;
    switch (f) {
      case 'draft':
        return st == PurchaseStatus.draft || st == PurchaseStatus.saved;
      case 'pending':
        return st == PurchaseStatus.confirmed;
      case 'paid':
        return st == PurchaseStatus.paid;
      case 'overdue':
        return st == PurchaseStatus.overdue;
      case 'due_today':
        final now = DateTime.now();
        final t = DateTime(now.year, now.month, now.day);
        if (p.dueDate == null) return false;
        final d = DateTime(p.dueDate!.year, p.dueDate!.month, p.dueDate!.day);
        return d == t &&
            st != PurchaseStatus.paid &&
            st != PurchaseStatus.cancelled;
      default:
        return true;
    }
  }

  bool _matchesSearch(TradePurchase p) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    if (p.humanId.toLowerCase().contains(q)) return true;
    if ((p.supplierName ?? '').toLowerCase().contains(q)) return true;
    if ((p.brokerName ?? '').toLowerCase().contains(q)) return true;
    if (p.itemsSummary.toLowerCase().contains(q)) return true;
    return false;
  }

  List<TradePurchase> _filterList(List<TradePurchase> all) {
    final f = _filterFromRoute();
    return all
        .where((p) => _matchesFilter(p, f))
        .where(_matchesSearch)
        .toList();
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
    try {
      await ref.read(hexaApiProvider).deleteTradePurchase(
            businessId: session.primaryBusiness.id,
            purchaseId: p.id,
          );
      ref.invalidate(tradePurchasesListProvider);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Deleted')));
    } catch (e) {
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
    for (final id in _selected.toList()) {
      try {
        await ref.read(hexaApiProvider).deleteTradePurchase(
              businessId: session.primaryBusiness.id,
              purchaseId: id,
            );
      } catch (_) {}
    }
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
    ref.invalidate(tradePurchasesListProvider);
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
    final rows = ref.watch(tradePurchasesListProvider);
    final filter = _filterFromRoute();

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
              tooltip: 'Refresh',
              onPressed: () => ref.invalidate(tradePurchasesListProvider),
              icon: const Icon(Icons.refresh_rounded,
                  color: HexaColors.neutral, size: 22),
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
                onRetry: () => ref.invalidate(tradePurchasesListProvider),
              ),
              data: (items) {
                final parsed = items
                    .map((e) => TradePurchase.fromJson(Map<String, dynamic>.from(e)))
                    .toList();
                final visible = _filterList(parsed);
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search supplier, ID, items…',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                          prefixIcon: const Icon(Icons.search_rounded),
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
                            ('pending', 'Pending'),
                            ('paid', 'Paid'),
                            ('overdue', 'Overdue'),
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(e.$2),
                                selected: filter == e.$1,
                                onSelected: (_) {
                                  final uri = e.$1 == 'all'
                                      ? '/purchase'
                                      : '/purchase?filter=${e.$1}';
                                  context.go(uri);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: visible.isEmpty
                          ? _HistoryEmpty(onAdd: () => context.push('/purchase/new'))
                          : ListView.separated(
                              key: PageStorageKey<String>('hist_${filter}_$_query'),
                              controller: _scroll,
                              padding: EdgeInsets.fromLTRB(
                                  16, 8, 16, 96 + MediaQuery.of(context).padding.bottom),
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
    final due = p.dueDate != null
        ? DateFormat.yMMMd().format(p.dueDate!)
        : '—';

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
                    Row(
                      children: [
                        Expanded(
                          child: Text(supp,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w800)),
                        ),
                        _MiniBadge(st),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.humanId} · ${DateFormat.yMMMd().format(p.purchaseDate)}',
                      style: const TextStyle(fontSize: 11, color: HexaColors.neutral),
                    ),
                    if (p.itemsSummary.isNotEmpty)
                      Text(
                        p.itemsSummary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: HexaColors.neutral),
                      ),
                    const SizedBox(height: 4),
                    Text('Due $due',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
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
