import 'package:flutter/material.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';

class UserPermissionGroup {
  const UserPermissionGroup({
    required this.title,
    required this.permissions,
  });

  final String title;
  final List<UserPermissionEntry> permissions;
}

class UserPermissionEntry {
  const UserPermissionEntry({
    required this.key,
    required this.label,
    this.subtitle,
  });

  final String key;
  final String label;
  final String? subtitle;
}

/// Grouped permission matrix — mirrors backend PERMISSION_KEYS.
const userPermissionGroups = <UserPermissionGroup>[
  UserPermissionGroup(
    title: 'Inventory',
    permissions: [
      UserPermissionEntry(
        key: 'stock_edit',
        label: 'Edit stock',
        subtitle: 'Adjust quantities and warehouse counts',
      ),
      UserPermissionEntry(
        key: 'delete_access',
        label: 'Delete items',
        subtitle: 'Remove catalog items and records',
      ),
    ],
  ),
  UserPermissionGroup(
    title: 'Purchases',
    permissions: [
      UserPermissionEntry(
        key: 'purchase_create',
        label: 'Create purchase',
      ),
      UserPermissionEntry(
        key: 'purchase_edit',
        label: 'Edit purchase',
      ),
    ],
  ),
  UserPermissionGroup(
    title: 'Reports',
    permissions: [
      UserPermissionEntry(
        key: 'reports_access',
        label: 'View reports',
      ),
      UserPermissionEntry(
        key: 'export_access',
        label: 'Export reports',
      ),
      UserPermissionEntry(
        key: 'analytics_access',
        label: 'Analytics dashboard',
      ),
    ],
  ),
  UserPermissionGroup(
    title: 'Printing',
    permissions: [
      UserPermissionEntry(
        key: 'barcode_print',
        label: 'Barcode print',
      ),
    ],
  ),
  UserPermissionGroup(
    title: 'Administration',
    permissions: [
      UserPermissionEntry(
        key: 'user_manage',
        label: 'Manage users',
      ),
    ],
  ),
];

class UserGroupedPermissions extends StatelessWidget {
  const UserGroupedPermissions({
    super.key,
    required this.draft,
    required this.readOnly,
    required this.onChanged,
  });

  final Map<String, bool> draft;
  final bool readOnly;
  final void Function(String key, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in userPermissionGroups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Text(
              group.title,
              style: HexaDsType.h3(context).copyWith(fontSize: 16),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < group.permissions.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _PermissionRow(
                    entry: group.permissions[i],
                    value: draft[group.permissions[i].key] ?? false,
                    readOnly: readOnly,
                    onChanged: (v) => onChanged(group.permissions[i].key, v),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.entry,
    required this.value,
    required this.readOnly,
    required this.onChanged,
  });

  final UserPermissionEntry entry;
  final bool value;
  final bool readOnly;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: readOnly ? null : () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    style: HexaDsType.bodyPrimary(context).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry.subtitle != null)
                    Text(entry.subtitle!, style: HexaDsType.bodySm(context)),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: readOnly ? null : onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}
