import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/hexa_ds_tokens.dart';
import '../../../core/theme/hexa_colors.dart';

enum UserListPrimaryFilter { all, active, inactive, blocked }

class UserListFilterState {
  const UserListFilterState({
    this.search = '',
    this.primary = UserListPrimaryFilter.all,
    this.roles = const {},
  });

  final String search;
  final UserListPrimaryFilter primary;
  final Set<String> roles;

  UserListFilterState copyWith({
    String? search,
    UserListPrimaryFilter? primary,
    Set<String>? roles,
  }) {
    return UserListFilterState(
      search: search ?? this.search,
      primary: primary ?? this.primary,
      roles: roles ?? this.roles,
    );
  }

  int get drawerActiveCount => roles.length;
}

final userListFilterProvider =
    StateProvider<UserListFilterState>((ref) => const UserListFilterState());

List<Map<String, dynamic>> applyUserListFilters(
  List<Map<String, dynamic>> rows,
  UserListFilterState filters,
) {
  Iterable<Map<String, dynamic>> it = rows;
  switch (filters.primary) {
    case UserListPrimaryFilter.active:
      it = it.where((u) => u['is_active'] == true && u['is_blocked'] != true);
    case UserListPrimaryFilter.inactive:
      it = it.where((u) => u['is_active'] != true && u['is_blocked'] != true);
    case UserListPrimaryFilter.blocked:
      it = it.where((u) => u['is_blocked'] == true);
    case UserListPrimaryFilter.all:
      break;
  }
  if (filters.roles.isNotEmpty) {
    it = it.where((u) {
      final r = (u['role']?.toString() ?? '').toLowerCase();
      if (filters.roles.contains('admin') && (r == 'admin' || r == 'owner')) {
        return true;
      }
      return filters.roles.contains(r);
    });
  }
  final q = filters.search.trim().toLowerCase();
  if (q.isNotEmpty) {
    it = it.where((u) {
      final name = (u['name']?.toString() ?? '').toLowerCase();
      final email = (u['email']?.toString() ?? '').toLowerCase();
      final phone = (u['phone']?.toString() ?? '').toLowerCase();
      return name.contains(q) || email.contains(q) || phone.contains(q);
    });
  }
  return it.toList();
}

int countForPrimaryFilter(
  List<Map<String, dynamic>> rows,
  UserListPrimaryFilter filter,
) {
  return applyUserListFilters(
    rows,
    UserListFilterState(primary: filter),
  ).length;
}

Future<void> showUserListFilterDrawer(
  BuildContext context,
  WidgetRef ref,
) async {
  var draft = ref.read(userListFilterProvider);
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setModal) {
          void toggleRole(String role) {
            setModal(() {
              final next = Set<String>.from(draft.roles);
              if (next.contains(role)) {
                next.remove(role);
              } else {
                next.add(role);
              }
              draft = draft.copyWith(roles: next);
            });
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Filter by role', style: HexaDsType.h3(ctx)),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Staff'),
                    value: draft.roles.contains('staff'),
                    onChanged: (_) => toggleRole('staff'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Manager'),
                    value: draft.roles.contains('manager'),
                    onChanged: (_) => toggleRole('manager'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Admin / Owner'),
                    value: draft.roles.contains('admin'),
                    onChanged: (_) => toggleRole('admin'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModal(() {
                              draft = draft.copyWith(roles: {});
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            ref.read(userListFilterProvider.notifier).state =
                                draft;
                            Navigator.pop(ctx);
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class UserListPrimaryFilterBar extends ConsumerWidget {
  const UserListPrimaryFilterBar({
    super.key,
    required this.rows,
  });

  final List<Map<String, dynamic>> rows;

  static const _filters = UserListPrimaryFilter.values;

  static String _label(UserListPrimaryFilter f) => switch (f) {
        UserListPrimaryFilter.all => 'All users',
        UserListPrimaryFilter.active => 'Active',
        UserListPrimaryFilter.inactive => 'Inactive',
        UserListPrimaryFilter.blocked => 'Blocked',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userListFilterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          for (final f in _filters) ...[
            _Chip(
              label: _label(f),
              count: countForPrimaryFilter(rows, f),
              selected: state.primary == f,
              onTap: () => ref.read(userListFilterProvider.notifier).state =
                  state.copyWith(primary: f),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? HexaColors.brandPrimary.withValues(alpha: 0.12)
          : HexaColors.brandCard,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? HexaColors.brandPrimary
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Text(
            '$label ($count)',
            style: HexaDsType.bodyPrimary(context).copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? HexaColors.brandPrimary : null,
            ),
          ),
        ),
      ),
    );
  }
}
