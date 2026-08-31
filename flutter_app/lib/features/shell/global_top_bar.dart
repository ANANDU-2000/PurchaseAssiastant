import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_notifier.dart' show sessionProvider;
import '../../core/auth/dashboard_role.dart' show dashboardRoleLabel;
import '../../core/providers/notifications_provider.dart'
    show notificationsUnreadCountProvider;
import '../../core/router/navigation_ext.dart';
import '../../core/theme/hexa_colors.dart';

/// Application-level top bar for desktop (>= 1024px).
///
/// Renders a fixed 48px bar at the top of the shell with:
/// - Left: business name / workspace context
/// - Center: global search trigger
/// - Right: notifications, help, user menu
///
/// This widget is part of the shell chrome — it does NOT use [AppBar].
class GlobalTopBar extends ConsumerWidget {
  const GlobalTopBar({super.key, this.onToggleSidebar});

  final VoidCallback? onToggleSidebar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final businessName =
        session?.primaryBusiness.effectiveDisplayTitle ?? 'Warehouse';
    final roleLabel = session != null ? dashboardRoleLabel(session) : 'Owner';
    final unreadCount = ref.watch(notificationsUnreadCountProvider);

    return Material(
      color: cs.surface,
      elevation: 0,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                // ── Sidebar toggle ──
                if (onToggleSidebar != null)
                  IconButton(
                    tooltip: 'Toggle sidebar',
                    icon: const Icon(Icons.menu_rounded, size: 20),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onToggleSidebar!();
                    },
                  ),
                const SizedBox(width: 4),
                // ── Business name ──
                Flexible(
                  child: Text(
                    businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: HexaColors.textOnLightSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: HexaColors.brandPrimary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    roleLabel,
                    style: tt.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: HexaColors.brandPrimary,
                    ),
                  ),
                ),
                const Spacer(),
                // ── Global search trigger ──
                _SearchTrigger(onTap: () => context.go('/search')),
                const SizedBox(width: 8),
                // ── Notifications ──
                IconButton(
                  tooltip: 'Notifications',
                  icon: Badge(
                    isLabelVisible: unreadCount > 0,
                    label: Text(
                      unreadCount > 99 ? '99+' : '$unreadCount',
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w800),
                    ),
                    child: const Icon(Icons.notifications_outlined, size: 20),
                  ),
                  onPressed: () =>
                      pushOverlayRoute(context, '/notifications'),
                ),
                // ── Help ──
                IconButton(
                  tooltip: 'Help & guide',
                  icon: const Icon(Icons.help_outline_rounded, size: 20),
                  onPressed: () =>
                      pushOverlayRoute(context, '/settings/help'),
                ),
                const SizedBox(width: 4),
                // ── User menu ──
                _UserMenu(
                  businessName: businessName,
                  roleLabel: roleLabel,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchTrigger extends StatelessWidget {
  const _SearchTrigger({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 240,
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Search…',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              '⌘K',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({
    required this.businessName,
    required this.roleLabel,
  });

  final String businessName;
  final String roleLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        if (v == 'settings') {
          pushOverlayRoute(context, '/settings');
        } else if (v == 'logout') {
          ref.read(sessionProvider.notifier).logout();
          context.go('/login');
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                businessName,
                style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                roleLabel,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.settings_outlined, size: 20),
            title: Text('Settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.logout_rounded, size: 20),
            title: Text('Sign out'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: CircleAvatar(
        radius: 14,
        backgroundColor: HexaColors.brandPrimary,
        child: Text(
          businessName.isNotEmpty ? businessName[0].toUpperCase() : '?',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
