import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/json_coerce.dart';
import '../../../core/models/session.dart';
import '../../../core/models/trade_purchase_models.dart';
import '../../../core/providers/home_dashboard_provider.dart'
    show HomeDashboardData, bustHomeDashboardVolatileCaches, homeDashboardDataProvider;
import '../../../core/providers/home_owner_dashboard_providers.dart'
    show
        activeSessionsCountProvider,
        homeRecentPurchasesCompactProvider,
        homeTodayDashboardDataProvider,
        stockAlertCountsProvider,
        stockAuditRecentHomeProvider,
        stockCriticalCountProvider,
        stockLowCountProvider,
        stockLowTopHomeProvider;
import '../../../core/providers/purchase_post_save_provider.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/notifications_provider.dart'
    show notificationsUnreadCountProvider;
import '../../../core/providers/prefs_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/providers/catalog_providers.dart';
import '../../../core/providers/stock_providers.dart';
import '../../../core/providers/suppliers_list_provider.dart';
import '../../../core/providers/reports_provider.dart';
import '../../../core/providers/trade_purchases_provider.dart'
    show invalidateTradePurchaseCaches, invalidateTradePurchaseCachesFromContainer;
import '../../../core/theme/hexa_colors.dart';
import '../../../shared/widgets/operational_ui.dart';
import '../../../shared/widgets/shell_quick_ref_actions.dart';
import '../../purchase/presentation/widgets/purchase_saved_sheet.dart';
import '../../purchase/presentation/widgets/resume_purchase_draft_banner.dart';

String _inr(num n) =>
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0)
        .format(n);

bool _sessionIsOwner(Session s) {
  final r = s.primaryBusiness.role.toLowerCase();
  return r == 'owner' || r == 'super_admin' || s.isSuperAdmin;
}

/// Harisree owner home: quick actions, today stats, stock, audits, recent purchases.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  Timer? _poll;
  Timer? _rtPoll;
  Timer? _resumeRefreshDebounce;
  bool _handlingPurchasePostSave = false;
  int _lastUnread = 0;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  late final AnimationController _livePulse;

  @override
  void initState() {
    super.initState();
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!mounted) return;
      bustHomeDashboardVolatileCaches();
      invalidateTradePurchaseCaches(ref);
      ref.invalidate(homeTodayDashboardDataProvider);
      ref.invalidate(stockAlertCountsProvider);
      ref.invalidate(stockLowTopHomeProvider);
      ref.invalidate(stockAuditRecentHomeProvider);
      ref.invalidate(activeSessionsCountProvider);
      ref.invalidate(homeRecentPurchasesCompactProvider);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _lastUnread = ref.read(notificationsUnreadCountProvider);
      }
    });
    _rtPoll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      ref.invalidate(stockListProvider);
      invalidateTradePurchaseCaches(ref);
      ref.invalidate(homeTodayDashboardDataProvider);
      ref.invalidate(stockAlertCountsProvider);
      ref.invalidate(stockLowTopHomeProvider);
      ref.invalidate(stockAuditRecentHomeProvider);
      ref.invalidate(homeRecentPurchasesCompactProvider);
      ref.invalidate(appNotificationUnreadCountProvider);
      _maybePushBackgroundAlert();
    });
  }

  @override
  void dispose() {
    _livePulse.dispose();
    _poll?.cancel();
    _rtPoll?.cancel();
    _resumeRefreshDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _maybePushBackgroundAlert() {
    if (!ref.read(localNotificationsOptInProvider)) return;
    final bg = _lifecycle == AppLifecycleState.paused ||
        _lifecycle == AppLifecycleState.hidden ||
        _lifecycle == AppLifecycleState.inactive;
    if (!bg) return;
    final unread = ref.read(notificationsUnreadCountProvider);
    if (unread <= _lastUnread) return;
    final delta = unread - _lastUnread;
    unawaited(
      LocalNotificationsService.instance.showStockOrInAppAlert(
        title: 'Harisree Agency',
        body: delta == 1
            ? 'You have 1 new alert'
            : 'You have $delta new alerts',
        payload: 'notifications',
      ),
    );
    _lastUnread = unread;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    _lifecycle = s;
    if (s == AppLifecycleState.resumed) {
      _lastUnread = ref.read(notificationsUnreadCountProvider);
    }
    if (s != AppLifecycleState.resumed) return;
    _resumeRefreshDebounce?.cancel();
    _resumeRefreshDebounce = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) {
        _resumeRefreshDebounce = null;
        return;
      }
      _resumeRefreshDebounce = null;
      unawaited(_refresh());
    });
  }

  Future<void> _refresh() async {
    bustHomeDashboardVolatileCaches();
    ref.invalidate(homeDashboardDataProvider);
    ref.invalidate(homeTodayDashboardDataProvider);
    ref.invalidate(stockLowCountProvider);
    ref.invalidate(stockCriticalCountProvider);
    ref.invalidate(stockLowTopHomeProvider);
    ref.invalidate(stockAuditRecentHomeProvider);
    ref.invalidate(activeSessionsCountProvider);
    ref.invalidate(homeRecentPurchasesCompactProvider);
    invalidateTradePurchaseCaches(ref);
    ref.invalidate(reportsPurchasesPayloadProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PurchasePostSavePayload?>(purchasePostSaveProvider, (prev, next) {
      if (next == null || _handlingPurchasePostSave) return;
      _handlingPurchasePostSave = true;
      unawaited(_doHandlePurchasePostSave(next));
    });

    final session = ref.watch(sessionProvider);
    final isOwner = session != null && _sessionIsOwner(session);
    final todayAsync = ref.watch(homeTodayDashboardDataProvider);
    final lowN = ref.watch(stockLowCountProvider);
    final critN = ref.watch(stockCriticalCountProvider);
    final sessionsN = ref.watch(activeSessionsCountProvider);
    final lowRows = ref.watch(stockLowTopHomeProvider);
    final audits = ref.watch(stockAuditRecentHomeProvider);
    final recentPurch = ref.watch(homeRecentPurchasesCompactProvider);
    final bellCount = ref.watch(notificationsUnreadCountProvider);
    final conn = ref.watch(connectivityResultsProvider);
    final offline =
        conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: HexaColors.brandBackground,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Harisree Agency',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    letterSpacing: -0.2,
                    color: Color(0xFF0F172A),
                  ),
                ),
                if (!offline) ...[
                  const SizedBox(width: 8),
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.45, end: 1).animate(
                      CurvedAnimation(
                        parent: _livePulse,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF2E7D32),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Live',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(width: 8),
                  Text(
                    'Offline',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ],
            ),
            Text(
              DateFormat('EEE, d MMM yyyy').format(DateTime.now()),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        actions: [
          if (session != null)
            PopupMenuButton<String>(
              tooltip: 'Account',
              offset: const Offset(0, 40),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.15),
                child: Text(
                  () {
                    final t = session.primaryBusiness.effectiveDisplayTitle;
                    return t.isNotEmpty ? t[0].toUpperCase() : 'H';
                  }(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: HexaColors.brandPrimary,
                  ),
                ),
              ),
              onSelected: (v) async {
                if (v == 'logout') {
                  await ref.read(sessionProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  enabled: false,
                  child: Text(
                    session.primaryBusiness.role.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Text('Sign out'),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: bellCount > 0,
              label: Text(
                bellCount > 99 ? '99+' : '$bellCount',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
              ),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          ShellQuickRefActions(
            onRefresh: _refresh,
            suppressToolbarSearch: true,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
            children: [
              const ResumePurchaseDraftBanner(),
              const SizedBox(height: 6),
              _CircularQuickActionsRow(
                isOwner: isOwner,
                onScan: () => context.push('/barcode/scan'),
                onAddStock: () => context.go('/stock'),
                onPurchase: () => context.push('/purchase/new'),
                onReports: () => context.go('/reports'),
                onBulkPrint: () => context.push('/barcode/bulk-print'),
                onUsers: () => context.push('/settings/users'),
              ),
              const SizedBox(height: 8),
              const _HomeCatalogChips(),
              const SizedBox(height: 10),
              OperationalSection(
                title: 'Low stock',
                dense: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => context.push('/stock/reorder'),
                      child: const Text('Reorder', style: TextStyle(fontSize: 12)),
                    ),
                    TextButton(
                      onPressed: () {
                        ref.read(stockListQueryProvider.notifier).state =
                            const StockListQuery(status: 'low', sort: 'stock_asc');
                        context.go('/stock');
                      },
                      child: const Text('All', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                child: _LowStockTable(rowsAsync: lowRows),
              ),
              const SizedBox(height: 10),
              OperationalSection(
                title: 'Recent stock updates',
                dense: true,
                child: _AuditRecentList(rowsAsync: audits),
              ),
              const SizedBox(height: 10),
              OperationalSection(
                title: "Today's purchases",
                dense: true,
                trailing: TextButton(
                  onPressed: () => context.go('/purchase'),
                  child: const Text('History', style: TextStyle(fontSize: 12)),
                ),
                child: _RecentPurchasesCompact(rowsAsync: recentPurch),
              ),
              const SizedBox(height: 10),
              _CompactStatsRow(
                todayAsync: todayAsync,
                lowN: lowN,
                critN: critN,
                sessionsN: sessionsN,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _doHandlePurchasePostSave(PurchasePostSavePayload payload) async {
    try {
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      container.invalidate(homeDashboardDataProvider);
      container.invalidate(homeTodayDashboardDataProvider);
      _invalidateOwnerCachesFromContainer(container);
      invalidateTradePurchaseCachesFromContainer(container);
      container.read(purchasePostSaveProvider.notifier).state = null;
      _handlingPurchasePostSave = false;
      if (!mounted) return;
      final route = await showPurchaseSavedSheet(
        context,
        ref,
        savedJson: payload.savedJson,
        wasEdit: payload.wasEdit,
      );
      if (!mounted) return;
      final sid = payload.savedJson['id']?.toString();
      if (route == 'edit_missing' && sid != null && sid.isNotEmpty) {
        context.go('/purchase/edit/$sid');
      } else if (route == 'detail' && sid != null && sid.isNotEmpty) {
        TradePurchase? seed;
        try {
          seed = TradePurchase.fromJson(
            Map<String, dynamic>.from(payload.savedJson),
          );
        } catch (_) {}
        if (!mounted) return;
        context.go('/purchase/detail/$sid', extra: seed);
      }
    } finally {
      _handlingPurchasePostSave = false;
    }
  }

  void _invalidateOwnerCachesFromContainer(ProviderContainer c) {
    c.invalidate(homeTodayDashboardDataProvider);
    c.invalidate(stockAlertCountsProvider);
    c.invalidate(stockLowTopHomeProvider);
    c.invalidate(stockAuditRecentHomeProvider);
    c.invalidate(activeSessionsCountProvider);
    c.invalidate(homeRecentPurchasesCompactProvider);
  }
}

class _CircularQuickActionsRow extends StatelessWidget {
  const _CircularQuickActionsRow({
    required this.isOwner,
    required this.onScan,
    required this.onAddStock,
    required this.onPurchase,
    required this.onReports,
    required this.onBulkPrint,
    required this.onUsers,
  });

  final bool isOwner;
  final VoidCallback onScan;
  final VoidCallback onAddStock;
  final VoidCallback onPurchase;
  final VoidCallback onReports;
  final VoidCallback onBulkPrint;
  final VoidCallback onUsers;

  @override
  Widget build(BuildContext context) {
    final actions = <({String label, IconData icon, VoidCallback onTap})>[
      (label: 'Scan', icon: Icons.qr_code_scanner_rounded, onTap: onScan),
      (label: 'Stock', icon: Icons.inventory_2_outlined, onTap: onAddStock),
      (label: 'Purchase', icon: Icons.add_shopping_cart_outlined, onTap: onPurchase),
      (label: 'Reports', icon: Icons.bar_chart_outlined, onTap: onReports),
      (label: 'Print', icon: Icons.print_outlined, onTap: onBulkPrint),
      if (isOwner) (label: 'Users', icon: Icons.group_outlined, onTap: onUsers),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            CircularQuickAction(
              icon: actions[i].icon,
              label: actions[i].label,
              onTap: actions[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeCatalogChips extends ConsumerWidget {
  const _HomeCatalogChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catsAsync = ref.watch(itemCategoriesListProvider);
    final suppliersAsync = ref.watch(suppliersListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        catsAsync.when(
          loading: () => const SizedBox(height: 34),
          error: (_, __) => const SizedBox.shrink(),
          data: (cats) {
            final names = [
              for (final c in cats)
                if ((c['name'] ?? '').toString().trim().isNotEmpty)
                  c['name'].toString().trim(),
            ];
            if (names.isEmpty) return const SizedBox.shrink();
            return OperationalPillRow(
              labels: names.take(12).toList(),
              onSelected: (name) {
                ref.read(stockListQueryProvider.notifier).state =
                    StockListQuery(category: name, page: 1);
                context.go('/stock');
              },
            );
          },
        ),
        const SizedBox(height: 6),
        suppliersAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (rows) {
            final names = [
              for (final s in rows)
                if ((s['name'] ?? '').toString().trim().isNotEmpty)
                  s['name'].toString().trim(),
            ];
            if (names.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Text(
                    'Suppliers',
                    style: HexaDsType.label(11, color: HexaDsColors.textMuted),
                  ),
                ),
                OperationalPillRow(
                  labels: names.take(10).toList(),
                  onSelected: (name) {
                    ref.read(stockListQueryProvider.notifier).state =
                        StockListQuery(q: name, page: 1);
                    context.go('/stock');
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CompactStatsRow extends StatelessWidget {
  const _CompactStatsRow({
    required this.todayAsync,
    required this.lowN,
    required this.critN,
    required this.sessionsN,
  });

  final AsyncValue<HomeDashboardData> todayAsync;
  final AsyncValue<int> lowN;
  final AsyncValue<int> critN;
  final AsyncValue<int> sessionsN;

  @override
  Widget build(BuildContext context) {
    final today = todayAsync.valueOrNull;
    final purchaseToday = today?.totalPurchase ?? 0;
    final countToday = today?.purchaseCount ?? 0;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        OperationalStatChip(
          label: 'Today',
          value: todayAsync.isLoading
              ? '…'
              : '${_inr(purchaseToday)} · $countToday',
        ),
        OperationalStatChip(
          label: 'Low',
          value: lowN.isLoading ? '…' : '${lowN.valueOrNull ?? 0}',
          tint: const Color(0xFFE65100),
        ),
        OperationalStatChip(
          label: 'Critical',
          value: critN.isLoading ? '…' : '${critN.valueOrNull ?? 0}',
          tint: const Color(0xFFC62828),
        ),
        OperationalStatChip(
          label: 'Sessions',
          value: sessionsN.isLoading ? '…' : '${sessionsN.valueOrNull ?? 0}',
        ),
      ],
    );
  }
}

class _LowStockTable extends StatelessWidget {
  const _LowStockTable({required this.rowsAsync});

  final AsyncValue<List<Map<String, dynamic>>> rowsAsync;

  @override
  Widget build(BuildContext context) {
    return rowsAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      error: (e, _) => Text('Could not load low stock', style: TextStyle(color: Colors.red.shade700)),
      data: (rows) {
        if (rows.isEmpty) {
          return Text(
            'No low-stock items',
            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  rows[i]['name']?.toString() ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                subtitle: Text(
                  '${rows[i]['current_stock'] ?? '—'} / ${rows[i]['reorder_level'] ?? '—'} ${rows[i]['unit'] ?? ''}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  (rows[i]['stock_status'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: HexaColors.brandPrimary,
                  ),
                ),
                onTap: () {
                  final id = rows[i]['id']?.toString();
                  if (id != null && id.isNotEmpty) {
                    context.push('/catalog/item/$id');
                  }
                },
              ),
              if (i < rows.length - 1)
                const Divider(height: 1, indent: 12, endIndent: 12),
            ],
          ],
        );
      },
    );
  }
}

String _auditDelta(Map<String, dynamic> r) {
  final n = coerceToDouble(r['new_qty']);
  final o = coerceToDouble(r['old_qty']);
  final d = n - o;
  if ((d - d.roundToDouble()).abs() < 1e-6) return d.round().toString();
  return d.toStringAsFixed(2);
}

class _AuditRecentList extends StatelessWidget {
  const _AuditRecentList({required this.rowsAsync});

  final AsyncValue<List<Map<String, dynamic>>> rowsAsync;

  @override
  Widget build(BuildContext context) {
    return rowsAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      error: (_, __) => const Text('Could not load stock audits'),
      data: (rows) {
        if (rows.isEmpty) {
          return Text('No recent adjustments', style: TextStyle(color: Colors.grey.shade600));
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  (rows[i]['adjustment_type'] ?? 'Update').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  subtitle: Text(
                    '${rows[i]['updated_by_name'] ?? '—'} · ${rows[i]['updated_at'] ?? ''}',
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    _auditDelta(rows[i]),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              if (i < rows.length - 1)
                const Divider(height: 1, indent: 12, endIndent: 12),
            ],
          ],
        );
      },
    );
  }
}

class _RecentPurchasesCompact extends StatelessWidget {
  const _RecentPurchasesCompact({required this.rowsAsync});

  final AsyncValue<List<Map<String, dynamic>>> rowsAsync;

  @override
  Widget build(BuildContext context) {
    return rowsAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(12),
        child: CircularProgressIndicator(strokeWidth: 2),
      )),
      error: (_, __) => const Text('Could not load purchases'),
      data: (rows) {
        if (rows.isEmpty) {
          return Text('No purchases today', style: TextStyle(color: Colors.grey.shade600));
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                title: Text(
                  rows[i]['supplier_name']?.toString() ?? rows[i]['bill_no']?.toString() ?? 'Purchase',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  subtitle: Text(
                    rows[i]['purchase_date']?.toString() ?? '',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Text(
                    _inr(coerceToDouble(rows[i]['total_amount'] ?? rows[i]['bill_total'] ?? 0)),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  onTap: () {
                    final id = rows[i]['id']?.toString();
                    if (id != null && id.isNotEmpty) {
                      context.push('/purchase/detail/$id');
                    }
                  },
                ),
              if (i < rows.length - 1)
                const Divider(height: 1, indent: 12, endIndent: 12),
            ],
          ],
        );
      },
    );
  }
}
