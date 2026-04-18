import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/connectivity_provider.dart';
import '../../core/theme/hexa_colors.dart';

/// Shell: Home | Reports | ⊕ FAB | History | Assistant
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const branchHome      = 0;
  static const branchReports   = 1;
  static const branchHistory   = 2;
  static const branchAssistant = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx       = navigationShell.currentIndex;
    final routePath = GoRouterState.of(context).uri.path;
    final conn      = ref.watch(connectivityResultsProvider);
    final offline   = conn.valueOrNull != null && isOfflineResult(conn.valueOrNull!);

    void go(int branch) {
      HapticFeedback.selectionClick();
      navigationShell.goBranch(branch);
    }

    final cs = Theme.of(context).colorScheme;

    // Hide docked FAB + bottom bar on Assistant so they never overlap the composer.
    // Prefer route path over branch index (index can disagree if navigation state is stale).
    final loc = routePath;
    final hideShellChrome =
        loc == '/assistant' || loc.startsWith('/assistant/');

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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.flash_on_rounded, size: 18, color: Color(0xFF1C1917)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Offline — showing cached data. New purchases need a connection.',
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
          Expanded(child: navigationShell),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: hideShellChrome ? null : _FabButton(idx: idx),
      bottomNavigationBar: hideShellChrome ? null : _BottomBar(idx: idx, go: go, cs: cs),
    );
  }
}

// ── FAB ────────────────────────────────────────────────────────────────────────

class _FabButton extends StatelessWidget {
  const _FabButton({required this.idx});
  final int idx;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      height: 60,
      margin: const EdgeInsets.only(top: 4),
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
          onTap: () {
            HapticFeedback.mediumImpact();
            context.push('/purchase/new');
          },
          child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
        ),
      ),
    );
  }
}

// ── BOTTOM BAR ─────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.idx, required this.go, required this.cs});
  final int idx;
  final void Function(int) go;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      color: cs.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              Expanded(
                child: _TabItem(
                  label: 'Home',
                  selected: idx == ShellScreen.branchHome,
                  icon: idx == ShellScreen.branchHome
                      ? Icons.grid_view_rounded
                      : Icons.grid_view_outlined,
                  onTap: () => go(ShellScreen.branchHome),
                ),
              ),
              Expanded(
                child: _TabItem(
                  label: 'Reports',
                  selected: idx == ShellScreen.branchReports,
                  icon: idx == ShellScreen.branchReports
                      ? Icons.bar_chart_rounded
                      : Icons.bar_chart_outlined,
                  onTap: () => go(ShellScreen.branchReports),
                ),
              ),
              const SizedBox(width: 72), // FAB notch gap
              Expanded(
                child: _TabItem(
                  label: 'History',
                  selected: idx == ShellScreen.branchHistory,
                  icon: idx == ShellScreen.branchHistory
                      ? Icons.receipt_long_rounded
                      : Icons.receipt_long_outlined,
                  onTap: () => go(ShellScreen.branchHistory),
                ),
              ),
              Expanded(
                child: _TabItem(
                  label: 'Assistant',
                  selected: idx == ShellScreen.branchAssistant,
                  icon: idx == ShellScreen.branchAssistant
                      ? Icons.chat_bubble_rounded
                      : Icons.chat_bubble_outline_rounded,
                  onTap: () => go(ShellScreen.branchAssistant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
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
    final active = selected ? HexaColors.brandPrimary : Colors.grey.shade500;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(
                  horizontal: selected ? 14 : 0, vertical: 2),
              decoration: selected
                  ? BoxDecoration(
                      color: HexaColors.brandPrimary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                    )
                  : null,
              child: Icon(icon, size: 22, color: active),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
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
