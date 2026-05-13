import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/hexa_ds_tokens.dart';
import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/hexa_colors.dart';
import 'shell_branch_provider.dart';

/// Shell: Home | Reports | History | Search + end FAB (new purchase).
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

    final cs = Theme.of(context).colorScheme;

    final loc = routePath;
    final hideShellChrome = loc.startsWith('/assistant') ||
        loc == '/reports' ||
        loc.startsWith('/reports/') ||
        loc == '/purchase';

    return Scaffold(
      key: const ValueKey<String>('main_shell'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
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
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
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
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      floatingActionButton: hideShellChrome ? null : const _FabButton(),
      bottomNavigationBar: hideShellChrome
          ? null
          : NavigationBar(
              height: 68,
              selectedIndex: idx,
              onDestinationSelected: go,
              backgroundColor: cs.surface,
              indicatorColor: HexaColors.brandPrimary.withValues(alpha: 0.12),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.grid_view_outlined),
                  selectedIcon: Icon(Icons.grid_view_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart_rounded),
                  label: 'Reports',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'History',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_rounded),
                  selectedIcon: Icon(Icons.manage_search_rounded),
                  label: 'Search',
                ),
              ],
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
        margin: const EdgeInsets.only(top: 2),
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
