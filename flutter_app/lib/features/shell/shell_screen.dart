import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../entries/presentation/entry_create_sheet.dart';

/// Shell: full-bleed [IndexedStack body] · bottom bar: Home | Entries | **+** | AI | Reports (no top brand strip).
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Branch indices: 0 home, 1 entries, 2 ai, 3 analytics (Reports)
  static const branchHome = 0;
  static const branchEntries = 1;
  static const branchAi = 2;
  static const branchAnalytics = 3;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final idx = navigationShell.currentIndex;

    void go(int branch) {
      navigationShell.goBranch(branch);
    }

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Material(
        elevation: 3,
        shadowColor: cs.shadow.withValues(alpha: 0.18),
        color: cs.surfaceContainer,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _ShellTab(
                    selected: idx == ShellScreen.branchHome,
                    icon: Icons.space_dashboard_outlined,
                    selectedIcon: Icons.space_dashboard_rounded,
                    label: 'Home',
                    onTap: () => go(ShellScreen.branchHome),
                  ),
                ),
                Expanded(
                  child: _ShellTab(
                    selected: idx == ShellScreen.branchEntries,
                    icon: Icons.receipt_long_outlined,
                    selectedIcon: Icons.receipt_long_rounded,
                    label: 'Entries',
                    onTap: () => go(ShellScreen.branchEntries),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: idx == ShellScreen.branchAi
                        ? const SizedBox.shrink()
                        : FloatingActionButton(
                            heroTag: 'shell_add_entry',
                            elevation: 2,
                            tooltip: 'Add purchase entry',
                            onPressed: () => showEntryCreateSheet(context),
                            child: const Icon(Icons.add_rounded, size: 26),
                          ),
                  ),
                ),
                Expanded(
                  child: _ShellTab(
                    selected: idx == ShellScreen.branchAi,
                    icon: Icons.smart_toy_outlined,
                    selectedIcon: Icons.smart_toy_rounded,
                    label: 'AI',
                    onTap: () => go(ShellScreen.branchAi),
                  ),
                ),
                Expanded(
                  child: _ShellTab(
                    selected: idx == ShellScreen.branchAnalytics,
                    icon: Icons.insights_outlined,
                    selectedIcon: Icons.insights_rounded,
                    label: 'Reports',
                    onTap: () => go(ShellScreen.branchAnalytics),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShellTab extends StatelessWidget {
  const _ShellTab({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? selectedIcon : icon,
              size: 24,
              color: selected ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
