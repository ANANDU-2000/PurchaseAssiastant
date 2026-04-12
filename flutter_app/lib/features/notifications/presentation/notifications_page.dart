import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/notifications_provider.dart';
import '../../../core/theme/hexa_colors.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  String _filter = 'all'; // all | alerts | reminders | system

  bool _matchesFilter(NotificationItem n) {
    switch (_filter) {
      case 'alerts':
        return n.type == NotificationType.priceAlert || n.type == NotificationType.profitLow;
      case 'reminders':
        return n.type == NotificationType.reminder;
      case 'system':
        return n.type == NotificationType.system || n.type == NotificationType.whatsapp;
      default:
        return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final items = ref.watch(notificationsProvider);
    final filtered = items.where(_matchesFilter).toList();
    final rel = DateFormat.Hm();

    return Scaffold(
      backgroundColor: HexaColors.canvas,
      appBar: AppBar(
        backgroundColor: HexaColors.canvas,
        surfaceTintColor: Colors.transparent,
        title: Text('Alerts & Reminders', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: HexaColors.textPrimary)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: HexaColors.textSecondary),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Notification settings',
            icon: const Icon(Icons.tune_rounded, color: HexaColors.textSecondary),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                backgroundColor: HexaColors.surfaceCard,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                builder: (ctx) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Preferences', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      Text(
                        'Price alerts, profit drop, daily summary, and WhatsApp status toggles will be available in a future update.',
                        style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary, height: 1.4),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                _FilterChip(label: 'All', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                _FilterChip(label: 'Alerts', selected: _filter == 'alerts', onTap: () => setState(() => _filter = 'alerts')),
                _FilterChip(label: 'Reminders', selected: _filter == 'reminders', onTap: () => setState(() => _filter = 'reminders')),
                _FilterChip(label: 'System', selected: _filter == 'system', onTap: () => setState(() => _filter = 'system')),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text('No notifications', style: tt.bodyMedium?.copyWith(color: HexaColors.textSecondary)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final n = filtered[i];
                      final color = switch (n.type) {
                        NotificationType.priceAlert => HexaColors.warning,
                        NotificationType.profitLow => HexaColors.loss,
                        NotificationType.reminder => HexaColors.primaryMid,
                        NotificationType.whatsapp => const Color(0xFF25D366),
                        _ => HexaColors.textSecondary,
                      };
                      final icon = switch (n.type) {
                        NotificationType.priceAlert => Icons.warning_amber_rounded,
                        NotificationType.profitLow => Icons.trending_down_rounded,
                        NotificationType.reminder => Icons.schedule_rounded,
                        NotificationType.whatsapp => Icons.chat_rounded,
                        _ => Icons.notifications_rounded,
                      };
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Material(
                          color: HexaColors.surfaceCard,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () {
                              ref.read(notificationsProvider.notifier).markRead(n.id);
                              final route = n.actionRoute;
                              if (route != null && route.isNotEmpty) context.go(route);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border(
                                  left: BorderSide(color: n.isRead ? HexaColors.border : color, width: n.isRead ? 1 : 3),
                                  top: BorderSide(color: HexaColors.border),
                                  right: BorderSide(color: HexaColors.border),
                                  bottom: BorderSide(color: HexaColors.border),
                                ),
                              ),
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: color.withValues(alpha: 0.2),
                                    child: Icon(icon, color: color, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(n.title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: HexaColors.textPrimary)),
                                        const SizedBox(height: 4),
                                        Text(n.subtitle, style: tt.bodySmall?.copyWith(color: HexaColors.textSecondary, height: 1.35)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(rel.format(n.createdAt), style: tt.labelSmall?.copyWith(color: HexaColors.textSecondary)),
                                      IconButton(
                                        icon: const Icon(Icons.close_rounded, size: 18),
                                        color: HexaColors.textSecondary,
                                        onPressed: () => ref.read(notificationsProvider.notifier).dismiss(n.id),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
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

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? HexaColors.primaryMid : HexaColors.surfaceElevated,
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
                color: selected ? const Color(0xFF04201C) : HexaColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
