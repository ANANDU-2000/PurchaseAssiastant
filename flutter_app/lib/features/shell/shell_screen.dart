import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/hexa_colors.dart';

/// Shell: [IndexedStack body] · bottom nav · Home | Purchase | Reports | Contacts | Assistant.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const branchHome = 0;
  static const branchPurchase = 1;
  static const branchReports = 2;
  static const branchContacts = 3;
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
      bottomNavigationBar: NavigationBar(
        height: 68,
        selectedIndex: idx,
        onDestinationSelected: go,
        backgroundColor: cs.surface,
        indicatorColor: HexaColors.accentInfo.withValues(alpha: 0.16),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note_rounded),
            label: 'Purchase',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt_rounded),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Assistant',
          ),
        ],
      ),
    );
  }
}
