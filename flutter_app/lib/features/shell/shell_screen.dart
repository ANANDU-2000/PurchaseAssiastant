import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/hexa_colors.dart';
import '../entries/presentation/entry_create_sheet.dart';

/// Shell: [IndexedStack body] · bottom nav · Home | Entries | (center +) | Catalog | Reports.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Branch indices: 0 home, 1 entries, 2 catalog (suppliers/items), 3 analytics, 4 assistant (hidden from nav)
  static const branchHome = 0;
  static const branchEntries = 1;
  static const branchContacts = 2;
  static const branchAnalytics = 3;
  static const branchAssistant = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = navigationShell.currentIndex;
    final routePath = GoRouterState.of(context).uri.path;
    final conn = ref.watch(connectivityResultsProvider);
    final offline =
        conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);

    void go(int branch) {
      HapticFeedback.selectionClick();
      navigationShell.goBranch(branch);
    }

    final cs = Theme.of(context).colorScheme;
    // Avoid double FAB on catalog and assistant screens.
    // Use both index and URL — on web/deep-link, currentIndex can briefly desync from path.
    final hideFabByIndex = idx == ShellScreen.branchContacts ||
        idx == ShellScreen.branchAssistant;
    final hideFabByPath =
        routePath.startsWith('/contacts') || routePath.startsWith('/assistant');
    final showShellPurchaseFab = !hideFabByIndex && !hideFabByPath;

    return Scaffold(
      key: ValueKey<String>('shell_${routePath}_$idx'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (offline)
            Material(
              color: const Color(0xFFF59E0B),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.flash_on_rounded,
                        size: 18, color: Color(0xFF1C1917)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline — showing cached data where available. New purchases need a connection.',
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: const Color(0xFF1C1917),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
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
      floatingActionButton: showShellPurchaseFab
          ? Tooltip(
              message: 'New purchase entry',
              child: Container(
                key: const ValueKey('shell_fab'),
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: cs.surface,
                  border: Border.all(
                    color: HexaColors.accentInfo.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      showEntryCreateSheet(context);
                    },
                    splashColor: HexaColors.accentInfo.withValues(alpha: 0.12),
                    highlightColor:
                        HexaColors.accentInfo.withValues(alpha: 0.06),
                    child: const SizedBox(
                      width: 56,
                      height: 56,
                      child: Icon(
                        Icons.add_rounded,
                        color: HexaColors.accentInfo,
                        size: 26,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        padding: EdgeInsets.zero,
        height: 72,
        elevation: 0,
        shadowColor: Colors.transparent,
        color: cs.surface,
        surfaceTintColor: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
                top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.9))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, -2),
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
                    icon: Icons.people_alt_outlined,
                    selectedIcon: Icons.people_alt_rounded,
                    label: 'Catalog',
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
    final muted = const Color(0xFF64748B);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          splashColor: HexaColors.accentInfo.withValues(alpha: 0.12),
          highlightColor: HexaColors.accentInfo.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: selected ? 40 : 32,
                    height: selected ? 40 : 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? HexaColors.accentInfo.withValues(alpha: 0.16)
                          : Colors.transparent,
                    ),
                    child: Icon(
                      selected ? selectedIcon : icon,
                      size: 20,
                      color: selected
                          ? HexaColors.accentInfo
                          : muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.labelSmall?.copyWith(
                      fontSize: 9,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? HexaColors.accentInfo
                          : muted,
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
