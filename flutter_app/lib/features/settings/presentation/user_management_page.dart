import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/business_users_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/widgets/list_skeleton.dart';

enum _UserFilter { all, active, staff, managers, admin, blocked, recent }

/// Owner / admin: warehouse user list, create staff, bulk actions, profile drill-down.
class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  _UserFilter _filter = _UserFilter.all;
  bool _selectMode = false;
  final Set<String> _selected = {};

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    Iterable<Map<String, dynamic>> it = rows;
    switch (_filter) {
      case _UserFilter.active:
        it = it.where((u) => u['is_active'] == true && u['is_blocked'] != true);
        break;
      case _UserFilter.staff:
        it = it.where((u) => (u['role']?.toString() ?? '') == 'staff');
        break;
      case _UserFilter.managers:
        it = it.where((u) => (u['role']?.toString() ?? '') == 'manager');
        break;
      case _UserFilter.admin:
        it = it.where((u) {
          final r = u['role']?.toString() ?? '';
          return r == 'admin' || r == 'owner';
        });
        break;
      case _UserFilter.blocked:
        it = it.where((u) => u['is_blocked'] == true);
        break;
      case _UserFilter.recent:
        it = it.where((u) => _recentActive(u['last_active_at']?.toString()));
        break;
      case _UserFilter.all:
        break;
    }
    return it.toList();
  }

  static bool _recentActive(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return false;
    return DateTime.now().toUtc().difference(d.toUtc()) < const Duration(minutes: 5);
  }

  static String _relativeActive(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return 'No recent activity';
    final diff = DateTime.now().toUtc().difference(d.toUtc());
    if (diff < const Duration(minutes: 1)) return 'Active now';
    if (diff < const Duration(hours: 1)) return '${diff.inMinutes}m ago';
    if (diff < const Duration(days: 1)) return '${diff.inHours}h ago';
    return DateFormat.yMMMd().format(d.toLocal());
  }

  Color _roleColor(String role, ColorScheme cs) => switch (role) {
        'owner' => HexaColors.brandPrimary,
        'admin' => HexaColors.accentPurple,
        'manager' => const Color(0xFF2563EB),
        'staff' => cs.onSurfaceVariant,
        _ => cs.primary,
      };

  Future<void> _openCreateSheet() async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    final bid = session.primaryBusiness.id;
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    var role = 'staff';
    var active = true;
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              Future<void> submit() async {
                if (saving) return;
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                if (name.isEmpty || email.length < 5 || phone.length < 6) return;
                setModal(() => saving = true);
                try {
                  final body = await ref.read(hexaApiProvider).createBusinessUser(
                        businessId: bid,
                        fullName: name,
                        email: email,
                        phone: phone,
                        role: role,
                        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                        password: passCtrl.text.trim().isEmpty ? null : passCtrl.text.trim(),
                        isActive: active,
                      );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  invalidateUserManagementCaches(ref);
                  if (!mounted) return;
                  final user = body['user'] is Map
                      ? Map<String, dynamic>.from(body['user'] as Map)
                      : <String, dynamic>{};
                  final gen = body['generated_password']?.toString();
                  final pwd = gen ??
                      (passCtrl.text.trim().isNotEmpty ? passCtrl.text.trim() : null);
                  final loginEmail =
                      body['login_email']?.toString() ?? user['email']?.toString() ?? email;
                  if (pwd != null && pwd.isNotEmpty) {
                    await _showCredentialShareDialog(
                      context: context,
                      user: user,
                      password: pwd,
                      loginEmail: loginEmail,
                    );
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User created')),
                    );
                  }
                } on DioException catch (e) {
                  setModal(() => saving = false);
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(userFacingError(e))),
                  );
                } catch (e) {
                  setModal(() => saving = false);
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(userFacingError(e))),
                  );
                }
              }

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Add user', style: HexaDsType.formSectionLabel),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
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
                      onChanged: saving
                          ? null
                          : (v) => setModal(() => role = v ?? 'staff'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: passCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password (optional)',
                        helperText: 'Leave empty to generate a readable password',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      value: active,
                      onChanged: saving ? null : (v) => setModal(() => active = v),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: saving ? null : () => unawaited(submit()),
                      child: saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create user'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
    nameCtrl.dispose();
    emailCtrl.dispose();
    phoneCtrl.dispose();
    notesCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _showCredentialShareDialog({
    required BuildContext context,
    required Map<String, dynamic> user,
    required String password,
    required String loginEmail,
  }) async {
    final name = user['name']?.toString() ?? 'User';
    final phone = user['phone']?.toString() ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final lines = <String>[
      'Harisree workspace login',
      'Name: $name',
      'Email: $loginEmail',
      'Password: $password',
      if (phone.isNotEmpty) 'Phone: $phone',
    ];
    final msg = Uri.encodeComponent(lines.join('\n'));
    final wa = digits.length >= 10 ? Uri.parse('https://wa.me/$digits?text=$msg') : null;
    final copyText = lines.join('\n');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share credentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('Email: $loginEmail'),
            SelectableText(
              'Password: $password',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: copyText));
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Credentials copied')),
              );
            },
            child: const Text('Copy'),
          ),
          if (wa != null)
            TextButton(
              onPressed: () async {
                if (await canLaunchUrl(wa)) {
                  await launchUrl(wa, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('WhatsApp'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCredentials(String userId) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final creds = await ref.read(hexaApiProvider).getUserCredentials(
            businessId: session.primaryBusiness.id,
            userId: userId,
          );
      final email = creds['login_email']?.toString() ?? '';
      final note = creds['note']?.toString() ?? '';
      await Clipboard.setData(ClipboardData(text: '$email\n$note'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login email copied')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _resetPassword(String userId) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      final out = await ref.read(hexaApiProvider).resetBusinessUserPassword(
            businessId: session.primaryBusiness.id,
            userId: userId,
          );
      final pwd = out['new_password']?.toString() ?? '';
      final email = out['login_email']?.toString() ?? '';
      if (!mounted) return;
      await _showCredentialShareDialog(
        context: context,
        user: {'name': 'User'},
        password: pwd,
        loginEmail: email,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _patchUser(String userId, Map<String, dynamic> data) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).patchBusinessUser(
            businessId: session.primaryBusiness.id,
            userId: userId,
            fullName: data['full_name'] as String?,
            email: data['email'] as String?,
            phone: data['phone'] as String?,
            role: data['role'] as String?,
            isActive: data['is_active'] as bool?,
            isBlocked: data['is_blocked'] as bool?,
          );
      invalidateUserManagementCaches(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _deleteUser(String userId) async {
    final session = ref.read(sessionProvider);
    if (session == null) return;
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
            userId: userId,
          );
      invalidateUserManagementCaches(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  Future<void> _bulkAction(String action, {String? role}) async {
    if (_selected.isEmpty) return;
    final session = ref.read(sessionProvider);
    if (session == null) return;
    try {
      await ref.read(hexaApiProvider).bulkBusinessUsers(
            businessId: session.primaryBusiness.id,
            userIds: _selected.toList(),
            action: action,
            role: role,
          );
      setState(() {
        _selected.clear();
        _selectMode = false;
      });
      invalidateUserManagementCaches(ref);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(userFacingError(e))),
      );
    }
  }

  static String _filterLabel(_UserFilter f) => switch (f) {
        _UserFilter.all => 'All',
        _UserFilter.active => 'Active',
        _UserFilter.staff => 'Staff',
        _UserFilter.managers => 'Managers',
        _UserFilter.admin => 'Admin',
        _UserFilter.blocked => 'Blocked',
        _UserFilter.recent => 'Recent',
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final canCreate = session != null && sessionCanCreateUsers(session);
    final canAdmin = session != null && sessionCanAdminUsers(session);
    final async = ref.watch(businessUsersListProvider);

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _selectMode ? '${_selected.length} selected' : 'Users',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: Icon(_selectMode ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: () {
            if (_selectMode) {
              setState(() {
                _selectMode = false;
                _selected.clear();
              });
            } else {
              context.popOrGo('/settings');
            }
          },
        ),
        actions: [
          if (canAdmin)
            IconButton(
              tooltip: _selectMode ? 'Exit selection' : 'Select users',
              onPressed: () => setState(() {
                _selectMode = !_selectMode;
                if (!_selectMode) _selected.clear();
              }),
              icon: Icon(_selectMode ? Icons.check_box_rounded : Icons.checklist_rounded),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => invalidateUserManagementCaches(ref),
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (canCreate && !_selectMode)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: _openCreateSheet,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: const Text('Add'),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _selectMode && canAdmin
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => _bulkAction('activate'),
                      child: const Text('Activate'),
                    ),
                    OutlinedButton(
                      onPressed: () => _bulkAction('deactivate'),
                      child: const Text('Deactivate'),
                    ),
                    OutlinedButton(
                      onPressed: () => _bulkAction('block'),
                      child: const Text('Block'),
                    ),
                    OutlinedButton(
                      onPressed: () => _bulkAction('delete'),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: ListSkeleton(),
        ),
        error: (e, _) => HexaErrorCard.fromError(
          error: e,
          title: 'Could not load users',
          onRetry: () => invalidateUserManagementCaches(ref),
        ),
        data: (rows) {
          final filtered = _filtered(rows);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in _UserFilter.values)
                      FilterChip(
                        label: Text(_filterLabel(f)),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No users in this filter.',
                          style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          invalidateUserManagementCaches(ref);
                          await ref.read(businessUsersListProvider.future);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final u = filtered[i];
                            return _UserRowCard(
                              user: u,
                              selectMode: _selectMode,
                              selected: _selected.contains(u['id']?.toString()),
                              canAdmin: canAdmin,
                              roleColor: _roleColor(u['role']?.toString() ?? '', cs),
                              recentActive: _recentActive(u['last_active_at']?.toString()),
                              lastActiveLabel:
                                  _relativeActive(u['last_active_at']?.toString()),
                              onToggleSelect: () {
                                final id = u['id']?.toString() ?? '';
                                setState(() {
                                  if (_selected.contains(id)) {
                                    _selected.remove(id);
                                  } else {
                                    _selected.add(id);
                                  }
                                });
                              },
                              onTap: () {
                                final id = u['id']?.toString() ?? '';
                                if (_selectMode) {
                                  setState(() {
                                    if (_selected.contains(id)) {
                                      _selected.remove(id);
                                    } else {
                                      _selected.add(id);
                                    }
                                  });
                                  return;
                                }
                                if (id.isNotEmpty) context.push('/settings/users/$id');
                              },
                              onViewProfile: () {
                                final id = u['id']?.toString() ?? '';
                                if (id.isNotEmpty) context.push('/settings/users/$id');
                              },
                              onEdit: () {},
                              onBlock: () => _patchUser(
                                u['id']?.toString() ?? '',
                                {'is_blocked': true},
                              ),
                              onResetPassword: () =>
                                  _resetPassword(u['id']?.toString() ?? ''),
                              onDelete: () => _deleteUser(u['id']?.toString() ?? ''),
                              onCopyCredentials: () =>
                                  _copyCredentials(u['id']?.toString() ?? ''),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _UserRowCard extends StatelessWidget {
  const _UserRowCard({
    required this.user,
    required this.selectMode,
    required this.selected,
    required this.canAdmin,
    required this.roleColor,
    required this.recentActive,
    required this.lastActiveLabel,
    required this.onToggleSelect,
    required this.onTap,
    required this.onViewProfile,
    required this.onEdit,
    required this.onBlock,
    required this.onResetPassword,
    required this.onDelete,
    required this.onCopyCredentials,
  });

  final Map<String, dynamic> user;
  final bool selectMode;
  final bool selected;
  final bool canAdmin;
  final Color roleColor;
  final bool recentActive;
  final String lastActiveLabel;
  final VoidCallback onToggleSelect;
  final VoidCallback onTap;
  final VoidCallback onViewProfile;
  final VoidCallback onEdit;
  final VoidCallback onBlock;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;
  final VoidCallback onCopyCredentials;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final name = user['name']?.toString() ?? '—';
    final email = user['email']?.toString() ?? '';
    final role = user['role']?.toString() ?? '';
    final blocked = user['is_blocked'] == true;
    final active = user['is_active'] == true && !blocked;
    final isOwner = role == 'owner';

    String statusLabel;
    Color statusColor;
    if (blocked) {
      statusLabel = 'Blocked';
      statusColor = const Color(0xFFDC2626);
    } else if (active) {
      statusLabel = 'Active';
      statusColor = const Color(0xFF15803D);
    } else {
      statusLabel = 'Inactive';
      statusColor = cs.onSurfaceVariant;
    }

    return Card(
      color: context.adaptiveCard,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelect(),
                  ),
                ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: cs.primaryContainer,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (recentActive && active)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: const Color(0xFF22C55E),
                          shape: BoxShape.circle,
                          border: Border.all(color: context.adaptiveCard, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      lastActiveLabel,
                      style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      role.toUpperCase(),
                      style: tt.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: roleColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusLabel,
                    style: tt.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (canAdmin && !selectMode)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      onSelected: (v) {
                        switch (v) {
                          case 'profile':
                            onViewProfile();
                          case 'reset':
                            onResetPassword();
                          case 'block':
                            onBlock();
                          case 'copy':
                            onCopyCredentials();
                          case 'delete':
                            if (!isOwner) onDelete();
                        }
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'profile', child: Text('View profile')),
                        const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                        if (!isOwner)
                          const PopupMenuItem(value: 'block', child: Text('Block')),
                        const PopupMenuItem(value: 'copy', child: Text('Copy credentials')),
                        if (!isOwner)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
