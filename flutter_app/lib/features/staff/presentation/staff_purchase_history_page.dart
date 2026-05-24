import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/staff_home_providers.dart';
import '../../../core/providers/trade_purchases_provider.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/utils/line_display.dart';
import '../../../core/utils/unit_utils.dart';
import '../../../core/widgets/friendly_load_error.dart';
import '../../../core/widgets/list_skeleton.dart';

/// Staff purchase list — Today / Week / All time / Low stock items tabs.
class StaffPurchaseHistoryPage extends ConsumerStatefulWidget {
  const StaffPurchaseHistoryPage({super.key});

  @override
  ConsumerState<StaffPurchaseHistoryPage> createState() =>
      _StaffPurchaseHistoryPageState();
}

class _StaffPurchaseHistoryPageState extends ConsumerState<StaffPurchaseHistoryPage>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  late final TabController _tabs;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
  }

  bool _inPeriod(TradePurchase p, int tabIndex) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(
      p.purchaseDate.year,
      p.purchaseDate.month,
      p.purchaseDate.day,
    );
    return switch (tabIndex) {
      0 => d == today,
      1 => !d.isBefore(today.subtract(Duration(days: now.weekday - 1))),
      2 => true,
      _ => true,
    };
  }

  List<TradePurchase> _filterPurchases(List<TradePurchase> all) {
    final tab = _tabs.index;
    return all.where((p) {
      if (tab < 3 && !_inPeriod(p, tab)) return false;
      if (_query.isEmpty) return true;
      final hay = [
        p.humanId,
        p.supplierName ?? '',
        for (final l in p.lines) l.itemName,
      ].join(' ').toLowerCase();
      return hay.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final listAsync = ref.watch(tradePurchasesParsedProvider);
    final lowAsync = ref.watch(staffLowStockAlertsProvider);
    final tab = _tabs.index;

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Purchase orders'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          onTap: (_) => setState(() {}),
          tabs: [
            const Tab(text: 'Today'),
            const Tab(text: 'Week'),
            const Tab(text: 'All time'),
            Tab(
              text: lowAsync.maybeWhen(
                data: (rows) => 'Low stock (${rows.length})',
                orElse: () => 'Low stock',
              ),
            ),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tab < 3) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search supplier, order no., item…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _searchCtrl.clear(),
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE0DDD8)),
                  ),
                ),
              ),
            ),
          ],
          Expanded(
            child: tab == 3
                ? lowAsync.when(
                    loading: () =>
                        const ListSkeleton(rowCount: 8, rowHeight: 72),
                    error: (_, __) => FriendlyLoadError(
                      message: 'Could not load low stock items',
                      onRetry: () =>
                          ref.invalidate(staffLowStockAlertsProvider),
                    ),
                    data: (rows) {
                      if (rows.isEmpty) {
                        return Center(
                          child: Text(
                            'No low stock items',
                            style: HexaDsType.body(
                              14,
                              color: HexaDsColors.textMuted,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final item = rows[i];
                          final name = item['name']?.toString() ?? '—';
                          final cur = coerceToDouble(item['current_stock']);
                          final reorder =
                              coerceToDouble(item['reorder_level']);
                          final unit = item['unit']?.toString() ?? '';
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: ListTile(
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Text(
                                '${formatStockQtyNumber(cur)} / '
                                '${formatStockQtyNumber(reorder)} $unit',
                              ),
                              trailing: const Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFDC2626),
                              ),
                              onTap: () {
                                final id = item['id']?.toString();
                                if (id != null && id.isNotEmpty) {
                                  context.push('/catalog/item/$id');
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  )
                : listAsync.when(
                    loading: () =>
                        const ListSkeleton(rowCount: 8, rowHeight: 72),
                    error: (_, __) => FriendlyLoadError(
                      message: 'Could not load purchase history',
                      onRetry: () => ref.invalidate(tradePurchasesListProvider),
                    ),
                    data: (rows) {
                      final filtered = _filterPurchases(rows);
                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            _query.isEmpty
                                ? 'No purchase orders in this period'
                                : 'No orders match your search',
                            style: HexaDsType.body(
                              14,
                              color: HexaDsColors.textMuted,
                            ),
                          ),
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final p = filtered[i];
                          return _StaffPurchaseRow(
                            purchase: p,
                            onTap: () => context.push(
                              '/staff/purchase-history/${p.id}',
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StaffPurchaseRow extends StatelessWidget {
  const _StaffPurchaseRow({required this.purchase, required this.onTap});

  final TradePurchase purchase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sup = purchase.supplierName ?? 'Supplier';
    final initials = sup.isNotEmpty ? sup[0].toUpperCase() : '?';
    final date = purchase.purchaseDate;
    final ago = _relativeAge(date);
    final summary = purchase.lines
        .take(3)
        .map((l) {
          final q = formatLineQtyWeightFromTradeLine(l);
          return '${l.itemName} · $q';
        })
        .join(' · ');
    final statusLabel = purchase.isDelivered ? 'Delivered' : 'Pending';
    final statusColor =
        purchase.isDelivered ? const Color(0xFF0F766E) : const Color(0xFFD97706);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F766E),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      purchase.humanId,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '$sup · ${DateFormat('dd MMM').format(date)} · $ago',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (summary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _relativeAge(DateTime date) {
  final now = DateTime.now();
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return '$diff d ago';
}
