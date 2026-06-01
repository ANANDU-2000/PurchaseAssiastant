import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design_system/hexa_ds_tokens.dart';
import '../../../../core/design_system/hexa_operational_tokens.dart';
import '../../../../core/theme/theme_context_ext.dart';
import '../../users/user_last_active.dart';

/// Compact desktop preview panel for selected user.
class UserManagementDetailPanel extends StatelessWidget {
  const UserManagementDetailPanel({
    super.key,
    required this.user,
    required this.canAdmin,
    required this.onPatch,
    required this.onResetPassword,
    required this.onDelete,
    required this.onBlock,
  });

  final Map<String, dynamic>? user;
  final bool canAdmin;
  final Future<void> Function(Map<String, dynamic> data) onPatch;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return ColoredBox(
        color: context.adaptiveScaffold,
        child: Center(
          child: Text('Select a user', style: HexaDsType.bodySm(context)),
        ),
      );
    }

    final name = user!['name']?.toString() ?? '—';
    final email = user!['email']?.toString() ?? '';
    final phone = user!['phone']?.toString() ?? '';
    final role = user!['role']?.toString() ?? '';
    final active = user!['is_active'] == true && user!['is_blocked'] != true;
    final blocked = user!['is_blocked'] == true;
    final isOwner = role == 'owner';
    final lastActive = UserLastActive.label(
      user!['last_active_at']?.toString(),
      createdAtIso: user!['created_at']?.toString(),
    );

    return ColoredBox(
      color: context.adaptiveScaffold,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: HexaDsType.heading(20)),
                    Text(
                      UserRoleStyle.displayRole(role),
                      style: HexaDsType.bodySm(context).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (email.isNotEmpty) Text(email, style: HexaDsType.bodySm(context)),
          if (phone.isNotEmpty) Text(phone, style: HexaDsType.bodySm(context)),
          const SizedBox(height: 8),
          Text('Last active: $lastActive', style: HexaDsType.labelCaps(context)),
          Text(
            'Status: ${UserRoleStyle.statusLabel(blocked: blocked, active: active)}',
            style: HexaDsType.bodySm(context).copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: HexaOp.touchTargetMin,
            child: FilledButton(
              onPressed: () {
                final id = user!['id']?.toString() ?? '';
                if (id.isNotEmpty) context.push('/settings/users/$id');
              },
              child: const Text('Open full profile'),
            ),
          ),
          if (canAdmin && !isOwner) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz_rounded),
                onSelected: (v) {
                  switch (v) {
                    case 'reset':
                      onResetPassword();
                    case 'block':
                      onBlock();
                    case 'deactivate':
                      onPatch({'is_active': false});
                    case 'activate':
                      onPatch({'is_active': true});
                    case 'delete':
                      onDelete();
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'reset', child: Text('Reset password')),
                  if (!blocked)
                    const PopupMenuItem(value: 'block', child: Text('Block')),
                  if (active)
                    const PopupMenuItem(value: 'deactivate', child: Text('Deactivate'))
                  else if (!blocked)
                    const PopupMenuItem(value: 'activate', child: Text('Activate')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
