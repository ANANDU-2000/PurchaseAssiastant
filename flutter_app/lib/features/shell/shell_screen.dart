import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/hexa_ds_tokens.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/hexa_colors.dart';
import 'shell_branch_provider.dart';

/// Shell: Home | Reports | History | Search in one row, then [+] (no overlap).
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = navigationShell.currentIndex;
    final prevBranch = ref.read(shellCurrentBranchProvider);
    if (prevBranch != idx) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (ref.read(shellCurrentBranchProvider) != idx) {
          ref.read(shellCurrentBranchProvider.notifier).state = idx;
        }
      });
    }
    final routePath = GoRouterState.of(context).uri.path;
    final conn = ref.watch(connectivityResultsProvider);
    final offline =
        conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);

    void go(int branch) {
      HapticFeedback.selectionClick();
      navigationShell.goBranch(branch);
    }

    final loc = routePath;
    final hideShellChrome = loc.startsWith('/assistant') ||
        loc == '/reports' ||
        loc.startsWith('/reports/') ||
        loc == '/purchase';

    // Do not use a shell [Scaffold] with [bottomNavigationBar]: on web, nested
    // GoRouter [Navigator]s can interact badly with scaffold body layout so the
    // body gets ~zero height while the bar still paints — it then looks vertically
    // centered with a blank page. [SizedBox.expand] + [Column] keeps tabs + bar as
    // explicit flex siblings (see also [NoTransitionPage] in app_router).
    return SizedBox.expand(
      child: Material(
        key: const ValueKey<String>('main_shell'),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (offline)
              Semantics(
                liveRegion: true,
                container: true,
                label: "You're offline — showing cached data",
                child: Material(
                  color: const Color(0xFFF59E0B),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HexaDsLayout.pageGutter,
                      vertical: HexaDsSpace.xs + 2,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            size: 18, color: Color(0xFF1C1917)),
                        const SizedBox(width: HexaDsLayout.inlineGap),
                        Expanded(
                          child: Text(
                            "You're offline — showing cached data",
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
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
              ),
            Expanded(child: navigationShell),
            if (!hideShellChrome)
              _ShellBottomBar(
                selectedIndex: idx,
                onDestinationSelected: go,
              ),
          ],
        ),
      ),
    );
  }
}

class _ShellBottomBar extends StatelessWidget {
  const _ShellBottomBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _fabOuter = 60.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      shadowColor: Colors.black26,
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth;
                    final per = maxW > 0 ? maxW / 4 : 0.0;
                    var w = math.max(42.0, per);
                    if (w * 4 > maxW) {
                      w = per;
                    }
                    return Row(
                      children: [
                        SizedBox(
                          width: w,
                          child: _ShellNavTile(
                            selected: selectedIndex == 0,
                            icon: Icons.grid_view_outlined,
                            selectedIcon: Icons.grid_view_rounded,
                            label: 'Home',
                            onTap: () => onDestinationSelected(0),
                          ),
                        ),
                        SizedBox(
                          width: w,
                          child: _ShellNavTile(
                            selected: selectedIndex == 1,
                            icon: Icons.bar_chart_outlined,
                            selectedIcon: Icons.bar_chart_rounded,
                            label: 'Reports',
                            onTap: () => onDestinationSelected(1),
                          ),
                        ),
                        SizedBox(
                          width: w,
                          child: _ShellNavTile(
                            selected: selectedIndex == 2,
                            icon: Icons.receipt_long_outlined,
                            selectedIcon: Icons.receipt_long_rounded,
                            label: 'History',
                            onTap: () => onDestinationSelected(2),
                          ),
                        ),
                        SizedBox(
                          width: w,
                          child: _ShellNavTile(
                            selected: selectedIndex == 3,
                            icon: Icons.search_rounded,
                            selectedIcon: Icons.manage_search_rounded,
                            label: 'Search',
                            onTap: () => onDestinationSelected(3),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: _fabOuter,
                child: Center(
                  child: const _FabButton(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellNavTile extends StatelessWidget {
  const _ShellNavTile({
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
    final ic = selected ? selectedIcon : icon;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? HexaColors.brandPrimary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                ic,
                size: 24,
                color: selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FabButton extends StatelessWidget {
  const _FabButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'New purchase',
      button: true,
      enabled: true,
      excludeSemantics: true,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: HexaColors.ctaGradient,
          shape: BoxShape.circle,
          boxShadow: HexaColors.heroShadow(),
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.mediumImpact();
              context.push('/purchase/new');
            },
            child: const Icon(Icons.add_rounded, size: 26, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
