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
    final onPurchaseBranch = idx == branchPurchase;

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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: FloatingActionButton(
          tooltip: onPurchaseBranch ? 'Purchase list' : 'Quick purchase entry',
          backgroundColor: HexaColors.primaryMid,
          foregroundColor: Colors.white,
          elevation: 2,
          onPressed: () {
            HapticFeedback.mediumImpact();
            if (onPurchaseBranch) {
              context.go('/purchase');
              return;
            }
            context.push('/purchase/new');
          },
          child: const Icon(Icons.edit_note_rounded),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: cs.surface,
        elevation: 6,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 66,
            child: Row(
              children: [
                Expanded(
                  child: _ShellTabItem(
                    label: 'Home',
                    icon: idx == branchHome
                        ? Icons.grid_view_rounded
                        : Icons.grid_view_outlined,
                    selected: idx == branchHome,
                    onTap: () => go(branchHome),
                  ),
                ),
                Expanded(
                  child: _ShellTabItem(
                    label: 'Reports',
                    icon: idx == branchReports
                        ? Icons.bar_chart_rounded
                        : Icons.bar_chart_outlined,
                    selected: idx == branchReports,
                    onTap: () => go(branchReports),
                  ),
                ),
                const SizedBox(width: 72),
                Expanded(
                  child: _ShellTabItem(
                    label: 'Contacts',
                    icon: idx == branchContacts
                        ? Icons.people_alt_rounded
                        : Icons.people_alt_outlined,
                    selected: idx == branchContacts,
                    onTap: () => go(branchContacts),
                  ),
                ),
                Expanded(
                  child: _ShellTabItem(
                    label: 'Assistant',
                    icon: idx == branchAssistant
                        ? Icons.chat_bubble_rounded
                        : Icons.chat_bubble_outline_rounded,
                    selected: idx == branchAssistant,
                    onTap: () => go(branchAssistant),
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

class _ShellTabItem extends StatelessWidget {
  const _ShellTabItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = selected ? HexaColors.primaryMid : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: active),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: active,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
