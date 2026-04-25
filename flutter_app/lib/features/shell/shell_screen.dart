import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design_system/hexa_ds_tokens.dart';
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

    final bottomFabClearance = hideShellChrome
        ? 0.0
        : 56.0 + MediaQuery.viewPaddingOf(context).bottom;

    // Stable key: tab switches must NOT rebuild the entire shell (would drop branch state).
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
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomFabClearance),
              child: navigationShell,
            ),
          ),
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
    return Semantics(
      label: 'New purchase',
      button: true,
      enabled: true,
      excludeSemantics: true,
      child: Container(
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
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.mediumImpact();
              context.push('/purchase/new');
            },
            child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
          ),
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
          height: 64,
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
    final cs = Theme.of(context).colorScheme;
    final active =
        selected ? HexaColors.brandPrimary : cs.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      hint: selected ? 'Current tab' : 'Switch to $label tab',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: HexaDsSpace.xs),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: active),
              const SizedBox(height: HexaDsSpace.xs),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      letterSpacing: 0.12,
                      color: active,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
              const SizedBox(height: HexaDsSpace.xs),
              AnimatedContainer(
                duration: HexaDsMotion.fast,
                curve: HexaDsMotion.enter,
                height: 3,
                width: selected ? 24 : 0,
                decoration: BoxDecoration(
                  color: HexaColors.brandPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
