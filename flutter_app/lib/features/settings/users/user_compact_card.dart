import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import '../../../core/theme/theme_context_ext.dart';
import 'user_last_active.dart';

/// Compact ERP user row for management list.
class UserCompactCard extends StatelessWidget {
  const UserCompactCard({
    super.key,
    required this.user,
    required this.selectMode,
    required this.selected,
    this.listHighlighted = false,
    required this.canAdmin,
    required this.onTap,
    required this.onToggleSelect,
    required this.onViewProfile,
    required this.onResetPassword,
    required this.onBlock,
    required this.onDelete,
    required this.onCopyCredentials,
  });

  final Map<String, dynamic> user;
  final bool selectMode;
  final bool selected;
  final bool listHighlighted;
  final bool canAdmin;
  final VoidCallback onTap;
  final VoidCallback onToggleSelect;
  final VoidCallback onViewProfile;
  final VoidCallback onResetPassword;
  final VoidCallback onBlock;
  final VoidCallback onDelete;
  final VoidCallback onCopyCredentials;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = user['name']?.toString() ?? '—';
    final email = user['email']?.toString() ?? '';
    final role = user['role']?.toString() ?? '';
    final blocked = user['is_blocked'] == true;
    final active = user['is_active'] == true && !blocked;
    final isOwner = role == 'owner';
    final online = UserLastActive.isOnlineNow(user['last_active_at']?.toString());
    final lastActive = UserLastActive.label(
      user['last_active_at']?.toString(),
      createdAtIso: user['created_at']?.toString(),
    );
    final status = UserRoleStyle.statusLabel(blocked: blocked, active: active);
    final statusColor = blocked
        ? const Color(0xFFDC2626)
        : (active ? const Color(0xFF15803D) : cs.onSurfaceVariant);

    return Material(
      color: listHighlighted
          ? HexaColors.brandPrimary.withValues(alpha: 0.06)
          : context.adaptiveCard,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectMode)
                SizedBox(
                  width: HexaOp.touchTargetMin,
                  height: HexaOp.touchTargetMin,
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelect(),
                  ),
                ),
              _Avatar(initial: name.isNotEmpty ? name[0].toUpperCase() : '?', online: online && active),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: HexaDsType.h3(context).copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      UserRoleStyle.displayRole(role),
                      style: HexaDsType.bodySm(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: HexaDsType.bodySm(context),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Last active: $lastActive',
                      style: HexaDsType.labelCaps(context).copyWith(
                        fontSize: 10,
                        letterSpacing: 0.15,
                      ),
                    ),
                    Text(
                      'Status: $status',
                      style: HexaDsType.bodySm(context).copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (canAdmin && !selectMode)
                SizedBox(
                  width: HexaOp.touchTargetMin,
                  height: HexaOp.touchTargetMin,
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz_rounded, size: 22),
                    tooltip: 'User actions',
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
                      const PopupMenuItem(value: 'copy', child: Text('Copy email')),
                      if (!isOwner)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initial, required this.online});

  final String initial;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: cs.primaryContainer,
          child: Text(
            initial,
            style: TextStyle(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}
