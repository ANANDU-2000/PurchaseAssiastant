import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_notifier.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/router/post_auth_route.dart';
import '../../core/theme/hexa_colors.dart';
import 'app_settings_action.dart';

/// Catalog, Contacts, optional Refresh, Search tab, Alerts, Settings.
class ShellQuickRefActions extends ConsumerWidget {
  const ShellQuickRefActions({
    super.key,
    this.onRefresh,
    this.showRefresh = true,
    this.suppressToolbarSearch = false,
  });

  final VoidCallback? onRefresh;
  final bool showRefresh;

  /// When true, omit the Search icon (Search lives on the bottom nav shell tab).
  final bool suppressToolbarSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Home',
          onPressed: () {
            final s = ref.read(sessionProvider);
            if (s != null) context.go(authenticatedHomePath(s));
          },
          icon: Icon(Icons.home_outlined, color: icon, size: 22),
          padding: const EdgeInsets.all(8),
        ),
        IconButton(
          tooltip: 'Catalog',
          onPressed: () => context.push('/catalog'),
          icon: Icon(Icons.inventory_2_outlined, color: icon, size: 22),
          padding: const EdgeInsets.all(8),
        ),
        IconButton(
          tooltip: 'Contacts',
          onPressed: () => context.push('/contacts'),
          icon: Icon(Icons.groups_outlined, color: icon, size: 22),
          padding: const EdgeInsets.all(8),
        ),
        if (showRefresh && onRefresh != null)
          IconButton(
            tooltip: 'Refresh',
            onPressed: onRefresh,
            icon: Icon(Icons.refresh_rounded, color: icon, size: 22),
            padding: const EdgeInsets.all(8),
          ),
        if (!suppressToolbarSearch)
          IconButton(
            tooltip: 'Search',
            onPressed: () => context.go('/search'),
            icon: Icon(Icons.search_rounded, color: icon, size: 22),
            padding: const EdgeInsets.all(8),
          ),
        _AlertsIconButton(icon: icon),
        const AppSettingsAction(),
        const SizedBox(width: 4),
      ],
    );
  }
}

class _AlertsIconButton extends ConsumerWidget {
  const _AlertsIconButton({required this.icon});
  final Color icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationsUnreadCountProvider);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Alerts',
          onPressed: () => context.push('/notifications'),
          icon: Icon(
            unread > 0 ? Icons.notifications_rounded : Icons.notifications_outlined,
            color: icon,
            size: 22,
          ),
          padding: const EdgeInsets.all(8),
        ),
        if (unread > 0)
          Positioned(
            right: 10,
            top: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: HexaColors.loss,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
