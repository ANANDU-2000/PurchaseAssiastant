import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_error_messages.dart';
import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/friendly_load_error.dart';
import 'stock_compact_update_sheet.dart';
import 'widgets/low_stock_category_tree.dart';
import 'widgets/reorder_level_sheet.dart';

/// Unified low-stock dashboard for owner and staff (category tree + tabs).
class LowStockDashboardPage extends ConsumerStatefulWidget {
  const LowStockDashboardPage({super.key, required this.staffMode});

  final bool staffMode;

  @override
  ConsumerState<LowStockDashboardPage> createState() =>
      _LowStockDashboardPageState();
}

class _LowStockDashboardPageState extends ConsumerState<LowStockDashboardPage>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 5;

  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _search = '';
  LowStockSearchScope _searchScope = LowStockSearchScope.all;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabCount, vsync: this);
    _searchCtrl.addListener(_onSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final filter = GoRouterState.of(context).uri.queryParameters['filter'];
      final idx = _tabIndexFromFilter(filter);
      if (idx != null && idx != _tabs.index) {
        _tabs.animateTo(idx);
      }
    });
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q == _search) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      setState(() => _search = q);
    });
  }

  int? _tabIndexFromFilter(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return switch (raw.trim().toLowerCase()) {
      'all' || 'low' => 0,
      'pending' => 1,
      'out' => 2,
      'purchased' => 3,
      'delivery' || 'pending_delivery' || 'pending-delivery' => 4,
      'delayed' || 'verification' || 'urgent' || 'high_impact' => 0,
      _ => null,
    };
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _notifyOwner(Map<String, dynamic> item) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final id = item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? 'Item';
    if (id.isEmpty) return;
    try {
      await ref.read(hexaApiProvider).notifyOwnerStockItem(
            businessId: session.primaryBusiness.id,
            itemId: id,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Owner notified about $name')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(e))),
      );
    }
  }

  Future<void> _editReorder(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = item['name']?.toString() ?? 'Item';
    final unit =
        item['stock_unit']?.toString() ?? item['unit']?.toString() ?? 'bag';
    final ok = await showReorderLevelSheet(
      context: context,
      ref: ref,
      itemId: id,
      itemName: name,
      unit: unit,
      currentReorder: reorderLevelFromStockRow(item),
    );
    if (ok && mounted) {
      ref.invalidate(lowStockByCategoryProvider);
    }
  }

  Future<void> _stockUpdate(Map<String, dynamic> item) async {
    final ok = await showStockCompactUpdateSheet(
      context: context,
      ref: ref,
      item: item,
    );
    if (ok && mounted) {
      ref.invalidate(lowStockByCategoryProvider);
    }
  }

  void _orderNow(Map<String, dynamic> item) {
    final id = item['id']?.toString();
    if (id != null && id.isNotEmpty) {
      context.push('/purchase/new?itemId=$id');
    } else {
      context.push('/purchase/new');
    }
  }

  void _receive(Map<String, dynamic> item) {
    final hid = item['last_purchase_human_id']?.toString();
    if (widget.staffMode) {
      if (hid != null && hid.isNotEmpty) {
        context.push('/staff/receive/$hid');
      } else {
        context.push('/staff/receive');
      }
    } else {
      context.push('/purchase');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupedAsync = ref.watch(lowStockByCategoryProvider);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('Low stock'),
        backgroundColor: Colors.transparent,
        foregroundColor: HexaColors.brandPrimary,
        bottom: groupedAsync.maybeWhen(
          data: (grouped) {
            final n = countLowStockForTab(grouped, LowStockTreeTab.allLow);
            return PreferredSize(
              preferredSize: const Size.fromHeight(168),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                    child: Text(
                      '$n items need attention',
                      style: HexaDsType.label(12, color: HexaDsColors.textMuted),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
                    child: Text(
                      'Period follows Home',
                      style: HexaDsType.label(10, color: HexaDsColors.textMuted),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        hintText: 'Search…',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final scope in LowStockSearchScope.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: FilterChip(
                                label: Text(_scopeLabel(scope)),
                                selected: _searchScope == scope,
                                onSelected: (_) =>
                                    setState(() => _searchScope = scope),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'All low ($n)'),
                      Tab(
                        text:
                            'Pending (${countLowStockForTab(grouped, LowStockTreeTab.pendingOrder)})',
                      ),
                      Tab(
                        text:
                            'Out (${countLowStockForTab(grouped, LowStockTreeTab.outOfStock)})',
                      ),
                      Tab(
                        text:
                            'Purchased (${countLowStockForTab(grouped, LowStockTreeTab.purchasedInPeriod)})',
                      ),
                      Tab(
                        text:
                            'Pending delivery (${countLowStockForTab(grouped, LowStockTreeTab.pendingDelivery)})',
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
          orElse: () => null,
        ),
      ),
      body: groupedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => FriendlyLoadError(
          message: 'Could not load low stock',
          onRetry: () => ref.invalidate(lowStockByCategoryProvider),
        ),
        data: (grouped) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(lowStockByCategoryProvider);
            await ref.read(lowStockByCategoryProvider.future);
          },
          child: TabBarView(
            controller: _tabs,
            children: [
              for (final tab in LowStockTreeTab.values)
                LowStockCategoryTree(
                  grouped: grouped,
                  tab: tab,
                  searchQuery: _search,
                  searchScope: _searchScope,
                  staffMode: widget.staffMode,
                  onOrderNow: widget.staffMode ? null : _orderNow,
                  onNotifyOwner: widget.staffMode ? _notifyOwner : null,
                  onEditReorder: _editReorder,
                  onStockUpdate: _stockUpdate,
                  onReceive: _receive,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _scopeLabel(LowStockSearchScope scope) => switch (scope) {
        LowStockSearchScope.all => 'All',
        LowStockSearchScope.category => 'Category',
        LowStockSearchScope.subcategory => 'Subcategory',
        LowStockSearchScope.item => 'Item',
      };
}
