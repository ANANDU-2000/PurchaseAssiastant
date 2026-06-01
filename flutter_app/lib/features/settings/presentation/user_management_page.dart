import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/auth/session_notifier.dart';
import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_responsive.dart';
import '../../../core/errors/user_facing_errors.dart';
import '../../../core/providers/business_users_provider.dart';
import '../../../core/router/navigation_ext.dart';
import '../../../core/router/post_auth_route.dart';
import '../../../core/theme/theme_context_ext.dart';
import '../../../core/widgets/hexa_error_card.dart';
import '../../../core/widgets/list_skeleton.dart';
import '../users/user_compact_card.dart';
import '../users/user_list_filters.dart';
import 'widgets/user_management_detail_panel.dart';

/// Owner / admin / manager: warehouse user list (ERP rebuild).
class UserManagementPage extends ConsumerStatefulWidget {
  const UserManagementPage({super.key});

  @override
  ConsumerState<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends ConsumerState<UserManagementPage> {
  bool _selectMode = false;
  final Set<String> _selected = {};
  final TextEditingController _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtl.text = ref.read(userListFilterProvider).search;
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

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

    await showHexaBottomSheet<void>(
      context: context,
      compact: false,
      padding: EdgeInsets.zero,
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
                  onChanged: saving ? null : (v) => setModal(() => role = v ?? 'staff'),
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

  Widget _searchBar(int filterBadge) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                hintText: 'Search users…',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) {
                ref.read(userListFilterProvider.notifier).state =
                    ref.read(userListFilterProvider).copyWith(search: v);
              },
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: filterBadge > 0,
            label: Text('$filterBadge'),
            child: IconButton(
              tooltip: 'Filter by role',
              onPressed: () => showUserListFilterDrawer(context, ref),
              icon: const Icon(Icons.tune_rounded),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider);
    final canCreate = session != null && sessionCanCreateUsers(session);
    final canAdmin = session != null && sessionCanAdminUsers(session);
    final async = ref.watch(businessUsersListProvider);
    final filterState = ref.watch(userListFilterProvider);

    return Scaffold(
      backgroundColor: context.adaptiveScaffold,
      appBar: AppBar(
        backgroundColor: context.adaptiveAppBarBg,
        surfaceTintColor: Colors.transparent,
        title: Text(
          _selectMode ? '${_selected.length} selected' : 'Users',
          style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, fontSize: 24),
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
                    OutlinedButton(onPressed: () => _bulkAction('activate'), child: const Text('Activate')),
                    OutlinedButton(onPressed: () => _bulkAction('deactivate'), child: const Text('Deactivate')),
                    OutlinedButton(onPressed: () => _bulkAction('block'), child: const Text('Block')),
                    OutlinedButton(onPressed: () => _bulkAction('delete'), child: const Text('Delete')),
                  ],
                ),
              ),
            )
          : null,
      body: async.when(
        loading: () => const Padding(padding: EdgeInsets.all(16), child: ListSkeleton()),
        error: (e, _) => HexaErrorCard.fromError(
          error: e,
          title: 'Could not load users',
          onRetry: () => invalidateUserManagementCaches(ref),
        ),
        data: (rows) {
          final filtered = applyUserListFilters(rows, filterState);
          final desktop = context.isDesktopLayout && !_selectMode;
          final selectedId = ref.watch(selectedUserIdProvider);
          Map<String, dynamic>? selectedUser;
          if (selectedId != null) {
            for (final u in filtered) {
              if (u['id']?.toString() == selectedId) {
                selectedUser = u;
                break;
              }
            }
          }
          if (desktop && filtered.isNotEmpty) {
            final sid = selectedId ?? filtered.first['id']?.toString();
            if (selectedId == null || selectedUser == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && sid != null) {
                  ref.read(selectedUserIdProvider.notifier).state = sid;
                }
              });
            }
          }

          Widget userList({required bool desktopSelect}) {
            if (filtered.isEmpty) {
              return Center(
                child: Text(
                  'No users match your filters.',
                  style: tt.bodyLarge,
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                invalidateUserManagementCaches(ref);
                await ref.read(businessUsersListProvider.future);
              },
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (ctx, i) {
                  final u = filtered[i];
                  final id = u['id']?.toString() ?? '';
                  return UserCompactCard(
                    user: u,
                    selectMode: _selectMode,
                    selected: _selected.contains(id),
                    listHighlighted: desktopSelect && selectedId == id,
                    canAdmin: canAdmin,
                    onToggleSelect: () {
                      setState(() {
                        if (_selected.contains(id)) {
                          _selected.remove(id);
                        } else {
                          _selected.add(id);
                        }
                      });
                    },
                    onTap: () {
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
                      if (desktopSelect && id.isNotEmpty) {
                        ref.read(selectedUserIdProvider.notifier).state = id;
                        return;
                      }
                      if (id.isNotEmpty) context.push('/settings/users/$id');
                    },
                    onViewProfile: () {
                      if (id.isNotEmpty) context.push('/settings/users/$id');
                    },
                    onBlock: () => _patchUser(id, {'is_blocked': true}),
                    onResetPassword: () => _resetPassword(id),
                    onDelete: () => _deleteUser(id),
                    onCopyCredentials: () => _copyCredentials(id),
                  );
                },
              ),
            );
          }

          final listChrome = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _searchBar(filterState.drawerActiveCount),
              UserListPrimaryFilterBar(rows: rows),
              Expanded(child: userList(desktopSelect: desktop)),
            ],
          );

          if (desktop) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 4, child: listChrome),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  flex: 5,
                  child: UserManagementDetailPanel(
                    user: selectedUser ?? (filtered.isNotEmpty ? filtered.first : null),
                    canAdmin: canAdmin,
                    onPatch: (data) => _patchUser(
                      selectedUser?['id']?.toString() ??
                          filtered.first['id']?.toString() ??
                          '',
                      data,
                    ),
                    onResetPassword: () => _resetPassword(
                      selectedUser?['id']?.toString() ?? '',
                    ),
                    onDelete: () => _deleteUser(
                      selectedUser?['id']?.toString() ?? '',
                    ),
                    onBlock: () => _patchUser(
                      selectedUser?['id']?.toString() ?? '',
                      {'is_blocked': true},
                    ),
                  ),
                ),
              ],
            );
          }

          return listChrome;
        },
      ),
    );
  }
}
