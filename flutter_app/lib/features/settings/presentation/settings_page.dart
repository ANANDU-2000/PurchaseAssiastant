import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/config/app_config.dart';
import '../../../core/models/session.dart';
import '../../../core/notifications/local_notifications_service.dart';
import '../../../core/platform/hexa_error_sink.dart';
import '../../../core/providers/business_aggregates_invalidation.dart';
import '../../../core/providers/prefs_provider.dart'
    show localNotificationsOptInProvider, notificationKindTogglesProvider;
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart'
    show sessionCanAdminUsers, sessionIsOwnerOrAdmin, sessionIsStaff;
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../shared/widgets/desktop_page_shell.dart';
import '../widgets/backup_monthly_banner.dart';

/// Settings categories for the left-nav architecture.
enum SettingsCategory {
  account('Account', Icons.person_outline_rounded),
  business('Business', Icons.business_rounded),
  notifications('Notifications', Icons.notifications_outlined),
  workspace('Workspace', Icons.workspaces_outlined),
  data('Data', Icons.folder_outlined),
  system('System', Icons.settings_outlined),
  troubleshooting('Troubleshooting', Icons.build_outlined);

  const SettingsCategory(this.label, this.icon);
  final String label;
  final IconData icon;
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  SettingsCategory _selectedCategory = SettingsCategory.account;
  int _superAdminGestureCount = 0;
  DateTime? _superAdminGestureAnchor;

  void _handleVersionLongPress(Session? session) {
    if (session?.isSuperAdmin != true) return;
    final now = DateTime.now();
    final anchor = _superAdminGestureAnchor;
    if (anchor == null || now.difference(anchor) > const Duration(seconds: 4)) {
      _superAdminGestureCount = 0;
    }
    _superAdminGestureAnchor = now;
    setState(() => _superAdminGestureCount++);
    if (_superAdminGestureCount >= 3) {
      _superAdminGestureCount = 0;
      _superAdminGestureAnchor = null;
      context.push('/admin');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final pb = session?.primaryBusiness;
    final tt = Theme.of(context).textTheme;
    final role = pb?.role.toLowerCase();
    final isStaff = session != null && sessionIsStaff(session);
    final isManager = role == 'manager';
    final isOwner = role == 'owner' || session?.isSuperAdmin == true;
    final isOwnerOrAdmin = session != null && sessionIsOwnerOrAdmin(session);
    final canManageUsers = session != null && sessionCanAdminUsers(session);
    final notifOptIn = ref.watch(localNotificationsOptInProvider);
    final notifKinds = ref.watch(notificationKindTogglesProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= 720;

    // Build the content for the selected category.
    final content = _buildCategoryContent(
      session: session,
      isStaff: isStaff,
      isManager: isManager,
      isOwner: isOwner,
      isOwnerOrAdmin: isOwnerOrAdmin,
      canManageUsers: canManageUsers,
      notifOptIn: notifOptIn,
      notifKinds: notifKinds,
    );

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Settings',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo(isStaff ? '/staff/home' : '/home'),
        ),
      ),
      body: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Left nav (fixed) ──
                _SettingsLeftNav(
                  selected: _selectedCategory,
                  onSelect: (cat) => setState(() => _selectedCategory = cat),
                  isStaff: isStaff,
                  isOwnerOrAdmin: isOwnerOrAdmin,
                  canManageUsers: canManageUsers,
                ),
                const VerticalDivider(width: 1),
                // ── Right content (scrollable) ──
                Expanded(
                  child: DesktopPageShell(
                    maxContentWidth: HexaResponsive.maxFormWidth,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    child: content,
                  ),
                ),
              ],
            )
          : DesktopPageShell(
              maxContentWidth: HexaResponsive.maxFormWidth,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: content,
            ),
    );
  }

  Widget _buildCategoryContent({
    required Session? session,
    required bool isStaff,
    required bool isManager,
    required bool isOwner,
    required bool isOwnerOrAdmin,
    required bool canManageUsers,
    required bool notifOptIn,
    required Set<String> notifKinds,
  }) {
    final cs = Theme.of(context).colorScheme;
    switch (_selectedCategory) {
      case SettingsCategory.account:
        return ListView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          children: [
            if (isOwner) const BackupMonthlyBanner(),
            _GroupHeader('Account'),
            _SettingsCard(
              children: [
                ListTile(
                  leading: Icon(Icons.person_outline_rounded, color: cs.primary),
                  title: const Text('Session'),
                  subtitle: Text(
                    session != null
                        ? 'Signed in · ${session.primaryBusiness.name}'
                        : 'Not signed in',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  await ref.read(sessionProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ),
          ],
        );

      case SettingsCategory.business:
        return _BusinessCategory(
          session: session,
          canManageUsers: canManageUsers,
          businessProfileReadOnly: isManager,
        );

      case SettingsCategory.notifications:
        return _NotificationsCategory(
          notifOptIn: notifOptIn,
          notifKinds: notifKinds,
          ref: ref,
        );

      case SettingsCategory.workspace:
        return _WorkspaceCategory(isStaff: isStaff, isOwner: isOwner);

      case SettingsCategory.data:
        return _DataCategory(isStaff: isStaff);

      case SettingsCategory.system:
        return _SystemCategory(
          isOwnerOrAdmin: isOwnerOrAdmin,
          isSuperAdmin: session?.isSuperAdmin == true,
        );

      case SettingsCategory.troubleshooting:
        return _TroubleshootingCategory(
          onVersionLongPress: () => _handleVersionLongPress(session),
        );
    }
  }
}

// ── Left Navigation ──

class _SettingsLeftNav extends StatelessWidget {
  const _SettingsLeftNav({
    required this.selected,
    required this.onSelect,
    required this.isStaff,
    required this.isOwnerOrAdmin,
    required this.canManageUsers,
  });

  final SettingsCategory selected;
  final ValueChanged<SettingsCategory> onSelect;
  final bool isStaff;
  final bool isOwnerOrAdmin;
  final bool canManageUsers;

  @override
  Widget build(BuildContext context) {
    final categories = SettingsCategory.values.where((cat) {
      // Filter categories based on role.
      if (cat == SettingsCategory.workspace && isStaff) return false;
      if (cat == SettingsCategory.system && !isOwnerOrAdmin) return false;
      return true;
    }).toList();

    return SizedBox(
      width: 220,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
        children: [
          for (final cat in categories)
            _SettingsNavTile(
              icon: cat.icon,
              label: cat.label,
              selected: selected == cat,
              onTap: () => onSelect(cat),
            ),
        ],
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  const _SettingsNavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? HexaColors.brandPrimary : cs.onSurface,
        ),
      ),
      selected: selected,
      selectedTileColor:
          HexaColors.brandPrimary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onTap: onTap,
    );
  }
}

// ── Category Content Widgets ──

class _BusinessCategory extends StatelessWidget {
  const _BusinessCategory({
    required this.session,
    required this.canManageUsers,
    this.businessProfileReadOnly = false,
  });

  final Session? session;
  final bool canManageUsers;
  final bool businessProfileReadOnly;

  @override
  Widget build(BuildContext context) {
    final pb = session?.primaryBusiness;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: [
        _GroupHeader('Business'),
        _SettingsCard(
          children: [
            ListTile(
              leading: Icon(Icons.business_rounded, color: cs.primary),
              title: Text(pb?.name ?? 'No business selected'),
              subtitle: session != null
                  ? Text(
                      'Role: ${pb!.role} · ${pb.effectiveDisplayTitle}',
                      style:
                          tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    )
                  : null,
            ),
            _NavTile(
              icon: Icons.receipt_long_outlined,
              title: 'Purchase order / business profile',
              subtitle: businessProfileReadOnly
                  ? 'View GSTIN, address, phone (read-only)'
                  : 'GSTIN, address, phone for purchase order PDFs',
              onTap: () => context.push(
                businessProfileReadOnly
                    ? '/settings/business?readonly=1'
                    : '/settings/business',
              ),
            ),
            if (canManageUsers)
              _NavTile(
                icon: Icons.group_outlined,
                title: 'Users & roles',
                subtitle: 'Staff and manager logins for this workspace',
                onTap: () => context.push('/settings/users'),
              ),
          ],
        ),
      ],
    );
  }
}

class _NotificationsCategory extends StatelessWidget {
  const _NotificationsCategory({
    required this.notifOptIn,
    required this.notifKinds,
    required this.ref,
  });

  final bool notifOptIn;
  final Set<String> notifKinds;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: [
        _GroupHeader('Notifications'),
        _SettingsCard(
          children: [
            SwitchListTile(
              secondary: Icon(Icons.notifications_active_outlined,
                  color: cs.primary),
              title: const Text('Local notifications'),
              subtitle: const Text(
                  'Warehouse reminders and follow-ups on this device'),
              value: notifOptIn,
              onChanged: (v) async {
                await ref
                    .read(localNotificationsOptInProvider.notifier)
                    .setValue(v);
                await LocalNotificationsService.instance.setOptIn(v);
              },
            ),
            if (notifOptIn) ...[
              SwitchListTile(
                title: const Text('Low stock alerts'),
                value: notifKinds.contains('low_stock'),
                onChanged: (v) => ref
                    .read(notificationKindTogglesProvider.notifier)
                    .setEnabled('low_stock', v),
              ),
              SwitchListTile(
                title: const Text('Delivery updates'),
                value: notifKinds.contains('delivery'),
                onChanged: (v) => ref
                    .read(notificationKindTogglesProvider.notifier)
                    .setEnabled('delivery', v),
              ),
              SwitchListTile(
                title: const Text('Stock variance'),
                value: notifKinds.contains('stock_variance'),
                onChanged: (v) => ref
                    .read(notificationKindTogglesProvider.notifier)
                    .setEnabled('stock_variance', v),
              ),
              SwitchListTile(
                title: const Text('Staff requests & reorder'),
                value: notifKinds.contains('staff_alert'),
                onChanged: (v) => ref
                    .read(notificationKindTogglesProvider.notifier)
                    .setEnabled('staff_alert', v),
              ),
              SwitchListTile(
                title: const Text('Opening stock reminders'),
                value: notifKinds.contains('opening_stock'),
                onChanged: (v) => ref
                    .read(notificationKindTogglesProvider.notifier)
                    .setEnabled('opening_stock', v),
              ),
              SwitchListTile(
                title: const Text('Evening physical count'),
                value: notifKinds.contains('physical_reminder'),
                onChanged: (v) => ref
                    .read(notificationKindTogglesProvider.notifier)
                    .setEnabled('physical_reminder', v),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _WorkspaceCategory extends StatelessWidget {
  const _WorkspaceCategory({required this.isStaff, required this.isOwner});

  final bool isStaff;
  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: [
        _GroupHeader('Workspace'),
        _SettingsCard(
          children: [
            _NavTile(
              icon: Icons.add_shopping_cart_outlined,
              title: 'New purchase',
              onTap: () => context.go('/purchase/new'),
            ),
            _NavTile(
              icon: Icons.history_rounded,
              title: 'Purchases',
              onTap: () => context.go('/purchase'),
            ),
            _NavTile(
              icon: Icons.playlist_add_check_rounded,
              title: 'Reorder list',
              subtitle: 'Items flagged for reorder',
              onTap: () => pushStockReorder(context),
            ),
            if (isOwner)
              _NavTile(
                icon: Icons.inventory_rounded,
                title: 'Opening stock setup',
                subtitle: 'Set initial stock and lock setup values',
                onTap: () => pushOpeningStockSetup(context),
              ),
            if (isOwner)
              _NavTile(
                icon: Icons.receipt_long_rounded,
                title: 'Staff cash purchases',
                subtitle: 'Quick buys logged by floor staff',
                onTap: () =>
                    pushOverlayRoute(context, '/stock/staff-purchases'),
              ),
            _NavTile(
              icon: Icons.print_outlined,
              title: 'Print barcodes (bulk)',
              onTap: () =>
                  pushOverlayRoute(context, '/barcode/bulk-print'),
            ),
            _NavTile(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Scan item',
              onTap: () => pushBarcodeScan(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _DataCategory extends StatelessWidget {
  const _DataCategory({required this.isStaff});

  final bool isStaff;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: [
        _GroupHeader('Data'),
        _SettingsCard(
          children: [
            _NavTile(
              icon: Icons.groups_outlined,
              title: 'Suppliers & brokers',
              subtitle: 'Contacts hub, categories, items, people',
              onTap: () => context.go('/contacts'),
            ),
            _NavTile(
              icon: Icons.category_outlined,
              title: 'Categories & subcategories',
              subtitle: 'Quick add Rice, Oil, and sub-types for items',
              onTap: () => context.push('/catalog/taxonomy'),
            ),
            if (!isStaff)
              _NavTile(
                icon: Icons.inventory_2_outlined,
                title: 'Item catalog',
                subtitle: 'Full category tree and item editor',
                onTap: () => context.push('/catalog'),
              ),
            _NavTile(
              icon: Icons.tune_rounded,
              title: 'Set reorder levels',
              subtitle: 'Thresholds for low-stock alerts',
              onTap: () => context.push('/catalog/setup-reorder-levels'),
            ),
            _NavTile(
              icon: Icons.qr_code_2_outlined,
              title: 'Missing item codes',
              subtitle: 'Assign codes and print barcodes',
              onTap: () => context.push('/catalog/missing-codes'),
            ),
            if (!isStaff)
              _NavTile(
                icon: Icons.cloud_download_outlined,
                title: 'Export & Backup',
                subtitle:
                    'Stock Excel, purchases PDF, ZIP trade data, auto-backup',
                onTap: () => context.push('/settings/backup'),
              ),
          ],
        ),
      ],
    );
  }
}

class _SystemCategory extends StatelessWidget {
  const _SystemCategory({
    required this.isOwnerOrAdmin,
    required this.isSuperAdmin,
  });

  final bool isOwnerOrAdmin;
  final bool isSuperAdmin;

  @override
  Widget build(BuildContext context) {
    if (!isOwnerOrAdmin) {
      return ListView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        children: [
          _GroupHeader('System'),
          _SettingsCard(
            children: [
              _NavTile(
                icon: Icons.checklist_outlined,
                title: 'Staff tasks',
                subtitle: 'Assignments for your team',
                onTap: () => context.push('/staff/tasks-board'),
              ),
            ],
          ),
        ],
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: [
        _GroupHeader('System'),
        _SettingsCard(
          children: [
            _NavTile(
              icon: Icons.vpn_key_outlined,
              title: 'API credentials',
              subtitle: 'Encrypted WhatsApp and AI provider keys',
              onTap: () => context.push('/settings/credentials'),
            ),
            _NavTile(
              icon: Icons.dashboard_customize_outlined,
              title: 'Owner command center',
              subtitle: 'Exceptions, stock, backup, staff tasks',
              onTap: () => context.push('/settings/owner-dashboard'),
            ),
            _NavTile(
              icon: Icons.checklist_outlined,
              title: 'Staff tasks',
              subtitle: 'All assignments and pending work',
              onTap: () => context.push('/staff/tasks-board'),
            ),
            if (isSuperAdmin)
              _NavTile(
                icon: Icons.admin_panel_settings_outlined,
                title: 'Super admin',
                onTap: () => context.push('/admin'),
              ),
          ],
        ),
      ],
    );
  }
}

class _TroubleshootingCategory extends ConsumerWidget {
  const _TroubleshootingCategory({required this.onVersionLongPress});

  final VoidCallback onVersionLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: [
        _GroupHeader('Troubleshooting'),
        _SettingsCard(
          children: [
            ListTile(
              leading: Icon(Icons.sync_rounded, color: cs.primary),
              title: const Text('Refresh all stats'),
              subtitle: const Text(
                'Reloads home, reports, contacts KPIs, and purchases from the server.',
              ),
              onTap: () {
                invalidateBusinessAggregates(ref);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Refreshing numbers...')),
                );
              },
            ),
            if (kDebugMode)
              ListTile(
                leading: Icon(Icons.bug_report_outlined, color: cs.error),
                title: const Text('Test error sink'),
                subtitle: const Text(
                  'Triggers a test exception to verify the production error sink fires.',
                ),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Throwing test exception…'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  Future<void>.delayed(const Duration(milliseconds: 500), () {
                    HexaErrorSink.triggerTestException();
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 28),
        Center(
          child: GestureDetector(
            onLongPress: onVersionLongPress,
            child: Text(
              'Version ${AppConfig.packageVersion}',
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared Widgets ──

class _GroupHeader extends StatelessWidget {
  const _GroupHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: context.adaptiveCard,
      clipBehavior: Clip.antiAlias,
      child: Column(children: _withDividers(children)),
    );
  }

  List<Widget> _withDividers(List<Widget> rows) {
    final out = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) out.add(const Divider(height: 1));
      out.add(rows[i]);
    }
    return out;
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
