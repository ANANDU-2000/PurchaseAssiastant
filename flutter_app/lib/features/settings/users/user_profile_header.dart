import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/design_system/hexa_operational_tokens.dart';
import '../../../core/theme/hexa_colors.dart';
import 'user_last_active.dart';

/// Expanded profile header content inside [SliverAppBar.flexibleSpace].
class UserProfileHeaderContent extends ConsumerWidget {
  const UserProfileHeaderContent({
    super.key,
    required this.user,
    required this.userId,
    required this.canAdmin,
    required this.onEdit,
    required this.onMoreSelected,
  });

  final Map<String, dynamic> user;
  final String userId;
  final bool canAdmin;
  final VoidCallback onEdit;
  final void Function(String action) onMoreSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = user['name']?.toString() ?? '—';
    final role = user['role']?.toString() ?? '';
    final blocked = user['is_blocked'] == true;
    final active = user['is_active'] == true && !blocked;
    final email = user['email']?.toString() ?? user['login_email']?.toString() ?? '';
    final phone = user['phone']?.toString() ?? '—';
    final warehouse = user['warehouse_name']?.toString() ??
        user['business_name']?.toString() ??
        '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final lastActive = UserLastActive.label(
      user['last_active_at']?.toString(),
      createdAtIso: user['created_at']?.toString(),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 56, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.15),
            child: Text(initial, style: HexaDsType.heading(20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: HexaDsType.heading(22),
                  maxLines: 2,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _pill(UserRoleStyle.displayRole(role)),
                    _pill(UserRoleStyle.statusLabel(blocked: blocked, active: active)),
                  ],
                ),
                if (warehouse.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Warehouse: $warehouse',
                    style: HexaDsType.bodySm(context),
                  ),
                ],
                const SizedBox(height: 4),
                if (email.isNotEmpty)
                  Text(email, style: HexaDsType.bodySm(context)),
                Text(phone, style: HexaDsType.bodySm(context)),
                Text(
                  'Last active: $lastActive',
                  style: HexaDsType.labelCaps(context).copyWith(fontSize: 10),
                ),
              ],
            ),
          ),
          if (canAdmin) ...[
            SizedBox(
              height: HexaOp.touchTargetMin,
              child: TextButton(
                onPressed: onEdit,
                child: const Text('Edit user'),
              ),
            ),
            SizedBox(
              width: HexaOp.touchTargetMin,
              height: HexaOp.touchTargetMin,
              child: PopupMenuButton<String>(
                tooltip: 'More actions',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: onMoreSelected,
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'reset',
                    child: Text('Reset password'),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Copy email'),
                  ),
                  if (role != 'owner') ...[
                    PopupMenuItem(
                      value: 'block',
                      child: Text(blocked ? 'Unblock' : 'Block'),
                    ),
                    PopupMenuItem(
                      value: 'toggle_active',
                      child: Text(active ? 'Deactivate' : 'Activate'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: HexaColors.brandPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: HexaDsType.body(11, weight: FontWeight.w700),
      ),
    );
  }
}

/// Collapsed title row when app bar scrolls.
class UserProfileCollapsedTitle extends StatelessWidget {
  const UserProfileCollapsedTitle({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  Widget build(BuildContext context) {
    final name = user['name']?.toString() ?? '—';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: HexaColors.brandPrimary.withValues(alpha: 0.15),
          child: Text(initial, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: HexaDsType.body(15, weight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
