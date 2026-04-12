import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/hexa_colors.dart';
import '../entries/presentation/entry_create_sheet.dart';

/// Shell: [IndexedStack body] · [BottomAppBar] with center notch + FAB · Home | Entries | Contacts | Reports.
/// AI/Voice opens from Home quick actions (`/ai`), not bottom nav.
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Branch indices: 0 home, 1 entries, 2 contacts, 3 analytics (Reports)
  static const branchHome = 0;
  static const branchEntries = 1;
  static const branchContacts = 2;
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
      floatingActionButton: FloatingActionButton(
        heroTag: 'shell_add_entry',
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: HexaColors.primaryMid,
        foregroundColor: Colors.white,
        tooltip: 'Add purchase entry',
        onPressed: () => showEntryCreateSheet(context),
        child: const Icon(Icons.add_rounded, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        padding: EdgeInsets.zero,
        height: 64,
        elevation: 3,
        shadowColor: cs.shadow.withValues(alpha: 0.18),
        color: cs.surfaceContainer,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SafeArea(
          top: false,
          child: Row(
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
              const SizedBox(width: 64),
              Expanded(
                child: _ShellTab(
                  selected: idx == ShellScreen.branchContacts,
                  icon: Icons.people_alt_outlined,
                  selectedIcon: Icons.people_alt_rounded,
                  label: 'Contacts',
                  onTap: () => go(ShellScreen.branchContacts),
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
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? selectedIcon : icon,
                size: 24,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(height: 2),
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
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 4,
                width: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
