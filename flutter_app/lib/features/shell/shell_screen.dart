import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/hexa_colors.dart';
import '../entries/presentation/entry_create_sheet.dart';

/// Shell: [IndexedStack body] · [BottomAppBar] with center notch + FAB · Home | Entries | Contacts | Reports.
/// AI/Voice opens from Home quick actions (`/ai`), not bottom nav.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Branch indices: 0 home, 1 entries, 2 contacts, 3 analytics (Reports)
  static const branchHome = 0;
  static const branchEntries = 1;
  static const branchContacts = 2;
  static const branchAnalytics = 3;

  static const _unselected = HexaColors.textSecondary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = navigationShell.currentIndex;
    final conn = ref.watch(connectivityResultsProvider);
    final offline = conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);

    void go(int branch) {
      navigationShell.goBranch(branch);
    }

    return Scaffold(
      backgroundColor: HexaColors.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offline)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    HexaColors.surfaceElevated,
                    HexaColors.surfaceCard,
                  ],
                ),
                border: Border(
                  bottom: BorderSide(color: HexaColors.warning.withValues(alpha: 0.35)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: HexaColors.accentPurple.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 20, color: HexaColors.warning.withValues(alpha: 0.95)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "You're offline. Reports and smart features need internet—entries may show last saved data.",
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: HexaColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(child: navigationShell),
        ],
      ),
      floatingActionButton: Container(
        key: const ValueKey('shell_fab'),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: HexaColors.ctaGradient,
          boxShadow: [
            ...HexaColors.glowShadow(HexaColors.accentPurple, blur: 22),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => showEntryCreateSheet(context),
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        padding: EdgeInsets.zero,
        height: 76,
        elevation: 0,
        shadowColor: Colors.transparent,
        color: HexaColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shape: const CircularNotchedRectangle(),
        notchMargin: 10,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: HexaColors.border)),
            boxShadow: [
              BoxShadow(
                color: HexaColors.accentPurple.withValues(alpha: 0.06),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Expanded(
                  child: _ShellTab(
                    selected: idx == ShellScreen.branchHome,
                    icon: Icons.grid_view_outlined,
                    selectedIcon: Icons.grid_view_rounded,
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
                    icon: Icons.people_outlined,
                    selectedIcon: Icons.people_rounded,
                    label: 'Contacts',
                    onTap: () => go(ShellScreen.branchContacts),
                  ),
                ),
                Expanded(
                  child: _ShellTab(
                    selected: idx == ShellScreen.branchAnalytics,
                    icon: Icons.bar_chart_outlined,
                    selectedIcon: Icons.bar_chart_rounded,
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
    final tt = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: HexaColors.accentPurple.withValues(alpha: 0.12),
          highlightColor: HexaColors.accentPurple.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  size: 24,
                  color: selected ? HexaColors.accentBlue : ShellScreen._unselected,
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                    color: selected ? HexaColors.accentBlue : ShellScreen._unselected,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 3,
                  width: selected ? 18 : 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: selected
                        ? LinearGradient(
                            colors: [
                              HexaColors.accentBlue,
                              HexaColors.accentPurple,
                            ],
                          )
                        : null,
                    color: selected ? null : Colors.transparent,
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
