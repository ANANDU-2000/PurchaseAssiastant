import 'package:flutter/material.dart';

import '../../../shared/widgets/desktop_page_shell.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/design_system/widgets/app_text_field.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/business_users_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../shared/widgets/hexa_empty_state.dart';
import '../users/user_activity_tab.dart';
import '../users/user_overview_kpi_grid.dart';
import '../users/user_permission_groups.dart';
import '../users/user_profile_header.dart';
import '../users/user_profile_providers.dart';

export '../users/user_profile_providers.dart';

/// Tabbed user profile — Overview / Activity / Permissions (ERP rebuild).
class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final out = await ref.read(hexaApiProvider).resetBusinessUserPassword(
            businessId: session.primaryBusiness.id,
            userId: widget.userId,
          );
      final pwd = out['new_password']?.toString() ?? '';
      final email = out['login_email']?.toString() ?? '';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('New password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (email.isNotEmpty) SelectableText('Email: $email'),
              SelectableText('Password: $pwd'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: pwd));
                Navigator.pop(ctx);
              },
              child: const Text('Copy & close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _handleMoreAction(String action, Map<String, dynamic> user) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final blocked = user['is_blocked'] == true;
    final active = user['is_active'] == true && !blocked;
    final email = user['email']?.toString() ?? user['login_email']?.toString() ?? '';

    switch (action) {
      case 'reset':
        await _resetPassword();
      case 'copy':
        if (email.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: email));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Email copied')),
        );
      case 'block':
        try {
          await ref.read(hexaApiProvider).patchBusinessUser(
                businessId: session.primaryBusiness.id,
                userId: widget.userId,
                isBlocked: !blocked,
              );
          ref.invalidate(businessUserProfileProvider(widget.userId));
          invalidateUserManagementCaches(ref);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userFacingError(e))),
          );
        }
      case 'toggle_active':
        try {
          await ref.read(hexaApiProvider).patchBusinessUser(
                businessId: session.primaryBusiness.id,
                userId: widget.userId,
                isActive: !active,
              );
          ref.invalidate(businessUserProfileProvider(widget.userId));
          invalidateUserManagementCaches(ref);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userFacingError(e))),
          );
        }
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete user?'),
            content: const Text('User will be deactivated. Audit history is kept.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok != true) return;
        try {
          await ref.read(hexaApiProvider).deleteBusinessUser(
                businessId: session.primaryBusiness.id,
                userId: widget.userId,
              );
          invalidateUserManagementCaches(ref);
          if (!mounted) return;
          context.popOrGo('/settings/users');
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(userFacingError(e))),
          );
        }
    }
  }

  Future<void> _openEditSheet(Map<String, dynamic> user) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final nameCtrl = TextEditingController(text: user['name']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: user['email']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: user['phone']?.toString() ?? '');
    var role = user['role']?.toString() ?? 'staff';
    final previousRole = role;
    var saving = false;

    await showHexaBottomSheet<void>(
      context: context,
      compact: true,
      padding: EdgeInsets.zero,
      child: StatefulBuilder(
        builder: (ctx, setModal) {
          Future<void> save() async {
            if (saving) return;
            setModal(() => saving = true);
            try {
              await ref.read(hexaApiProvider).patchBusinessUser(
                    businessId: session.primaryBusiness.id,
                    userId: widget.userId,
                    fullName: nameCtrl.text.trim(),
                    email: emailCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    role: role,
                  );
              ref.invalidate(businessUserProfileProvider(widget.userId));
              if (role != previousRole) {
                ref.invalidate(userPermissionsProvider(widget.userId));
              }
              invalidateUserManagementCaches(ref);
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              setModal(() => saving = false);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(userFacingError(e))),
              );
            }
          }

          // Keyboard inset is applied once by HexaResponsiveSheetViewport.
          return Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16,
              top: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit user', style: HexaDsType.h3(ctx)),
                const SizedBox(height: 12),
                AppTextField(
                  controller: nameCtrl,
                  label: 'Full name',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                AppTextField(
                  controller: emailCtrl,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 10),
                AppTextField(
                  controller: phoneCtrl,
                  label: 'Phone',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: 10),
                if ((user['role']?.toString() ?? '') != 'owner')
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: role,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'staff', child: Text('Staff')),
                      DropdownMenuItem(value: 'manager', child: Text('Manager')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    ],
                    onChanged:
                        saving ? null : (v) => setModal(() => role = v ?? role),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save changes'),
                ),
              ],
            ),
          );
        },
      ),
    );
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(businessUserProfileProvider(widget.userId));
    final session = ref.watch(sessionProvider);
    final canAdmin = session != null && sessionCanAdminUsers(session);

    return Scaffold(
      backgroundColor: HexaColors.brandBackground,
      appBar: AppBar(
        title: const Text('User profile'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.popOrGo('/settings/users'),
        ),
        backgroundColor: HexaColors.brandBackground,
        elevation: 0,
      ),
      body: DesktopPageShell(
        padding: EdgeInsets.zero,
        child: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => HexaErrorCard.fromError(
          error: e,
          title: 'Could not load user',
          onRetry: () => ref.invalidate(businessUserProfileProvider(widget.userId)),
        ),
        data: (user) {
          if (user.isEmpty) {
            return HexaEmptyState(
              icon: Icons.person_off_outlined,
              title: 'User not found',
              subtitle:
                  'This account may have been removed, or the link is out of date.',
              primaryActionLabel: 'Back to users',
              onPrimaryAction: () => context.popOrGo('/settings/users'),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UserProfileHeaderContent(
                user: user,
                userId: widget.userId,
                canAdmin: canAdmin,
                onEdit: () => _openEditSheet(user),
                onMoreSelected: (a) => _handleMoreAction(a, user),
              ),
              Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 1,
                child: TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: HexaDsType.body(13, weight: FontWeight.w700),
                  unselectedLabelStyle:
                      HexaDsType.body(13, weight: FontWeight.w600),
                  labelColor: HexaColors.brandPrimary,
                  unselectedLabelColor: HexaColors.textSecondary,
                  indicatorSize: TabBarIndicatorSize.label,
                  tabs: const [
                    Tab(text: 'Overview'),
                    Tab(text: 'Activity'),
                    Tab(text: 'Permissions'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _OverviewTab(user: user),
                    UserActivityTab(userId: widget.userId),
                    _PermissionsTab(
                      userId: widget.userId,
                      readOnly: !canAdmin,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.user});
  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const PageStorageKey('user_overview'),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        UserOverviewKpiGrid(user: user),
        const SizedBox(height: 12),
        if (user['notes'] != null && user['notes'].toString().isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notes', style: HexaDsType.labelCaps(context)),
                  const SizedBox(height: 4),
                  Text(user['notes'].toString()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _PermissionsTab extends ConsumerStatefulWidget {
  const _PermissionsTab({
    required this.userId,
    required this.readOnly,
  });

  final String userId;
  final bool readOnly;

  @override
  ConsumerState<_PermissionsTab> createState() => _PermissionsTabState();
}

class _PermissionsTabState extends ConsumerState<_PermissionsTab> {
  Map<String, bool>? _draft;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userPermissionsProvider(widget.userId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => UserProfilePermissionsLoadError(
        title: userFacingError(e),
        onRetry: () => ref.invalidate(userPermissionsProvider(widget.userId)),
      ),
      data: (body) {
        final perms = body['permissions'] is Map
            ? Map<String, dynamic>.from(body['permissions'] as Map)
            : <String, dynamic>{};
        _draft ??= perms.map((k, v) => MapEntry(k, v == true));
        final draft = _draft!;

        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            if (widget.readOnly)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'View only — only owners and admins can edit permissions.',
                  style: HexaDsType.bodySm(context),
                ),
              ),
            UserGroupedPermissions(
              draft: draft,
              readOnly: widget.readOnly,
              onChanged: (key, value) => setState(() => draft[key] = value),
            ),
            if (!widget.readOnly) ...[
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  final session = ref.read(sessionProvider);
                  if (session == null) return;
                  try {
                    await ref.read(hexaApiProvider).patchUserPermissions(
                          businessId: session.primaryBusiness.id,
                          userId: widget.userId,
                          permissions: draft,
                        );
                    ref.invalidate(userPermissionsProvider(widget.userId));
                    invalidateUserManagementCaches(ref);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Permissions saved')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(userFacingError(e))),
                    );
                  }
                },
                child: const Text('Save permissions'),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// User profile permissions tab load failure.
@visibleForTesting
class UserProfilePermissionsLoadError extends StatelessWidget {
  const UserProfilePermissionsLoadError({
    super.key,
    required this.title,
    required this.onRetry,
  });

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return HexaEmptyState(
      icon: Icons.admin_panel_settings_outlined,
      title: title,
      subtitle: 'Check your connection, then retry.',
      primaryActionLabel: 'Retry',
      onPrimaryAction: onRetry,
    );
  }
}
