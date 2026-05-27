import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/providers/notifications_provider.dart'
    show
        NotificationCategoryFilter,
        NotificationItem,
        mergedNotificationFeedProvider,
        notificationMatchesCategoryFilter,
        notificationsProvider;
import '../../../core/providers/realtime_notifications_provider.dart';
import '../../../core/providers/server_notifications_provider.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/errors/load_state_error.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import 'widgets/notification_alert_card.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  NotificationCategoryFilter _filter = NotificationCategoryFilter.all;
  final _textSearch = TextEditingController();
  var _primedFetch = false;

  @override
  void dispose() {
    _textSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_primedFetch) {
      _primedFetch = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.invalidate(appNotificationsListProvider);
        ref.invalidate(appNotificationUnreadCountProvider);
      });
    }
    ref.watch(realtimeNotificationsBoostProvider);
    final tt = Theme.of(context).textTheme;
    final serverAsync = ref.watch(appNotificationsListProvider);
    final items = ref.watch(mergedNotificationFeedProvider);
    final serverUnread =
        ref.watch(appNotificationUnreadCountProvider).valueOrNull ?? 0;
    final listEmptyButServerUnread =
        items.isEmpty && serverUnread > 0 && !serverAsync.isLoading;
    final filtered =
        items.where((n) => notificationMatchesCategoryFilter(n, _filter)).toList();
    final q = _textSearch.text.trim().toLowerCase();
    final visible = (q.isEmpty
            ? filtered
            : filtered
                .where((n) =>
                    '${n.title} ${n.subtitle}'.toLowerCase().contains(q))
                .toList())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final rel = DateFormat.Hm();
    final hasUnread = visible.any((n) => !n.isRead);
    final filterEmptyButHasItems =
        items.isNotEmpty && filtered.isEmpty && q.isEmpty;

    final onSurf = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text('Notifications',
            style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: onSurf)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          onPressed: () => context.popOrGo('/home'),
        ),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => _markAllRead(),
              child: const Text('Mark all read'),
            ),
          IconButton(
            tooltip: 'Clear server notifications',
            icon: Icon(Icons.delete_sweep_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: serverAsync.valueOrNull?.isEmpty == true
                ? null
                : () => _clearServerNotifications(),
          ),
          IconButton(
            tooltip: 'Notification settings',
            icon: Icon(Icons.tune_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: context.adaptiveCard,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) => Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    20 + MediaQuery.viewInsetsOf(ctx).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preferences',
                          style: tt.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Text(
                        'Price alerts, profit drop, daily summary, and WhatsApp status toggles will be available in a future update.',
                        style: tt.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.4),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (serverAsync.isLoading)
            const LinearProgressIndicator(minHeight: 2),
          if (serverAsync.hasError || listEmptyButServerUnread)
            Material(
              color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.35),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.warning_amber_rounded,
                    color: Theme.of(context).colorScheme.error),
                title: Text(
                  listEmptyButServerUnread
                      ? '$serverUnread alerts on server could not be loaded'
                      : 'Could not refresh server notifications',
                ),
                subtitle: Text(
                  listEmptyButServerUnread
                      ? 'Pull down to refresh. Warehouse alerts below are still shown.'
                      : loadStateErrorSubtitle(serverAsync.error),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    ref.invalidate(appNotificationsListProvider);
                    ref.invalidate(appNotificationUnreadCountProvider);
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: TextField(
              controller: _textSearch,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search alerts…',
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _textSearch.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _textSearch.clear();
                          setState(() {});
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in NotificationCategoryFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _FilterChip(
                        label: switch (f) {
                          NotificationCategoryFilter.all => 'All',
                          NotificationCategoryFilter.critical => 'Critical',
                          NotificationCategoryFilter.warehouse => 'Warehouse',
                          NotificationCategoryFilter.purchases => 'Purchases',
                          NotificationCategoryFilter.staff => 'Staff',
                          NotificationCategoryFilter.system => 'System',
                        },
                        selected: _filter == f,
                        onTap: () => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(appNotificationsListProvider);
                ref.invalidate(appNotificationUnreadCountProvider);
                await ref.read(appNotificationsListProvider.future);
              },
              child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.45,
                        child: Center(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                          Icon(
                            Icons.notifications_none_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            q.isNotEmpty
                                ? 'No matches'
                                : filterEmptyButHasItems
                                    ? _emptyTitleForFilter(_filter)
                                    : _emptyTitleForFilter(_filter),
                            textAlign: TextAlign.center,
                            style: tt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: onSurf,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            q.isNotEmpty
                                ? 'Try a different search or clear the search box.'
                                : filterEmptyButHasItems
                                    ? 'Switch to All or another tab — alerts are hidden by the current filter.'
                                    : _emptySubtitleForFilter(_filter),
                            textAlign: TextAlign.center,
                            style: tt.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                          if (filterEmptyButHasItems) ...[
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () => setState(
                                () => _filter = NotificationCategoryFilter.all,
                              ),
                              child: const Text('Show all alerts'),
                            ),
                          ],
                          if (items.isEmpty) ...[
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () => context.push('/purchase/new'),
                              icon: const Icon(Icons.add_shopping_cart_rounded,
                                  size: 20),
                              label: const Text('Record a purchase'),
                            ),
                          ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: _buildGroupedNotificationTiles(
                      context: context,
                      ref: ref,
                      visible: visible,
                      rel: rel,
                      tt: tt,
                    ),
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _markAllRead() async {
    final session = ref.read(sessionProvider);
    final api = ref.read(hexaApiProvider);
    if (session != null) {
      try {
        await api.markAllAppNotificationsRead(
          businessId: session.primaryBusiness.id,
        );
      } catch (_) {}
    }
    final items = ref.read(mergedNotificationFeedProvider);
    for (final n in items) {
      if (n.isRead) continue;
      if (n.serverNotificationId == null && !n.id.startsWith('pur_')) {
        ref.read(notificationsProvider.notifier).markRead(n.id);
      }
    }
    ref.invalidate(appNotificationsListProvider);
    ref.invalidate(appNotificationUnreadCountProvider);
    if (mounted) setState(() {});
  }

  Future<void> _clearServerNotifications() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Clear server notifications?'),
            content: const Text(
              'Stock alerts generated from live warehouse data will still appear until the stock issue is fixed.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Clear'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await ref.read(hexaApiProvider).clearAllAppNotifications(
          businessId: session.primaryBusiness.id,
        );
    ref.invalidate(appNotificationsListProvider);
    ref.invalidate(appNotificationUnreadCountProvider);
    if (mounted) setState(() {});
  }

  List<Widget> _buildGroupedNotificationTiles({
    required BuildContext context,
    required WidgetRef ref,
    required List<NotificationItem> visible,
    required DateFormat rel,
    required TextTheme tt,
  }) {
    if (visible.isEmpty) {
      return [
        const SizedBox(height: 80),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.notifications_none_rounded,
                  size: 48, color: Color(0xFFB0BEC5)),
              SizedBox(height: 12),
              Text(
                'No notifications yet',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              SizedBox(height: 4),
              Text(
                'Alerts will appear here when actions happen',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ];
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final widgets = <Widget>[];

    void addSection(String label, List<NotificationItem> section) {
      if (section.isEmpty) return;
      widgets.add(_NotificationDateHeader(label: label));
      for (final n in section) {
        widgets.add(_notificationTile(
          context: context,
          ref: ref,
          n: n,
          rel: rel,
          tt: tt,
        ));
      }
    }

    bool isToday(NotificationItem n) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      return d == today;
    }

    bool isYesterday(NotificationItem n) {
      final d = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      return d == yesterday;
    }

    addSection(
      'Today',
      visible.where(isToday).toList(),
    );
    addSection(
      'Yesterday',
      visible.where(isYesterday).toList(),
    );
    addSection(
      'Earlier',
      visible.where((n) => !isToday(n) && !isYesterday(n)).toList(),
    );
    return widgets;
  }

  Widget _notificationTile({
    required BuildContext context,
    required WidgetRef ref,
    required NotificationItem n,
    required DateFormat rel,
    required TextTheme tt,
  }) {
    Future<void> handleTap() async {
      final sid = n.serverNotificationId;
      if (sid != null && sid.isNotEmpty) {
        final session = ref.read(sessionProvider);
        if (session != null) {
          try {
            await ref.read(hexaApiProvider).patchAppNotificationRead(
                  businessId: session.primaryBusiness.id,
                  notificationId: sid,
                );
            invalidateNotificationSurfaces(ref);
          } catch (_) {}
        }
      } else if (!n.id.startsWith('pur_')) {
        ref.read(notificationsProvider.notifier).markRead(n.id);
      }
      final route = n.actionRoute;
      if (route != null && route.isNotEmpty && context.mounted) {
        context.push(route);
      }
    }

    return NotificationAlertCard(
      item: n,
      timeLabel: NotificationAlertCard.relativeTime(n.createdAt, rel),
      onTap: handleTap,
      onApprove: n.serverKind == 'approval_required'
          ? () => context.push('/stock/audits')
          : null,
      onReject: n.serverKind == 'approval_required'
          ? () => context.push('/stock/audits')
          : null,
    );
  }
}

class _NotificationDateHeader extends StatelessWidget {
  const _NotificationDateHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

String _emptyTitleForFilter(NotificationCategoryFilter filter) {
  return switch (filter) {
    NotificationCategoryFilter.all => 'No alerts yet',
    NotificationCategoryFilter.critical => 'No critical alerts',
    NotificationCategoryFilter.warehouse => 'No warehouse alerts',
    NotificationCategoryFilter.purchases => 'No purchase alerts',
    NotificationCategoryFilter.staff => 'No staff alerts',
    NotificationCategoryFilter.system => 'No system notifications',
  };
}

String _emptySubtitleForFilter(NotificationCategoryFilter filter) {
  return switch (filter) {
    NotificationCategoryFilter.all =>
      'Stock, purchase, and system activity will appear here.',
    NotificationCategoryFilter.critical =>
      'Mismatch, sync, and approval issues will show here when they occur.',
    NotificationCategoryFilter.warehouse =>
      'Low stock, barcodes, and opening stock alerts appear here.',
    NotificationCategoryFilter.purchases =>
      'Payment due, delivery pending, and invoice updates appear here.',
    NotificationCategoryFilter.staff =>
      'Staff corrections and warehouse requests appear here.',
    NotificationCategoryFilter.system =>
      'Exports, sync status, and general notices appear here.',
  };
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected
            ? HexaColors.primaryMid
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(
              label,
              style: tt.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
