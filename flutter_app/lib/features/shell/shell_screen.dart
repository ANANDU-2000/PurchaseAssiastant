import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../entries/presentation/entry_create_sheet.dart';

/// Shell: [History] in the top strip · body · bottom: Dashboard · Reports · [+] · Contacts · Voice
class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  /// Branch indices: 0 home, 1 entries, 2 analytics, 3 contacts, 4 voice
  static const _branchDashboard = 0;
  static const _branchEntries = 1;
  static const _branchAnalytics = 2;
  static const _branchContacts = 3;
  static const _branchVoice = 4;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final idx = navigationShell.currentIndex;
    final onHistory = idx == _branchEntries;

    void go(int branch) {
      navigationShell.goBranch(branch);
    }

    Widget dockItem({required int branch, required IconData icon, required IconData iconSel, required String label}) {
      final sel = !onHistory && idx == branch;
      return InkWell(
        onTap: () => go(branch),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(sel ? iconSel : icon, size: 24, color: sel ? cs.primary : cs.onSurfaceVariant),
              const SizedBox(height: 2),
              Text(
                label,
                style: tt.labelSmall?.copyWith(
                  fontWeight: sel ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 11,
                  color: sel ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            elevation: 0.5,
            color: cs.surfaceContainerLow,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.hub_rounded, size: 22, color: cs.primary),
                    const SizedBox(width: 8),
                    Text('HEXA', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        backgroundColor: onHistory ? cs.primaryContainer : cs.surfaceContainerHighest,
                      ),
                      onPressed: () => go(_branchEntries),
                      icon: Icon(
                        Icons.receipt_long_rounded,
                        size: 20,
                        color: onHistory ? cs.primary : cs.onSurfaceVariant,
                      ),
                      label: Text(
                        'History',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: onHistory ? cs.primary : cs.onSurfaceVariant,
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
      extendBody: true,
      floatingActionButton: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.35),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: FloatingActionButton(
          elevation: 3,
          onPressed: () => showEntryCreateSheet(context),
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButtonAnimator: FloatingActionButtonAnimator.scaling,
      bottomNavigationBar: BottomAppBar(
        elevation: 12,
        shadowColor: cs.shadow.withValues(alpha: 0.2),
        color: cs.surfaceContainer,
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        notchMargin: 14,
        shape: const CircularNotchedRectangle(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            dockItem(
              branch: _branchDashboard,
              icon: Icons.space_dashboard_outlined,
              iconSel: Icons.space_dashboard_rounded,
              label: 'Dashboard',
            ),
            dockItem(
              branch: _branchAnalytics,
              icon: Icons.insights_outlined,
              iconSel: Icons.insights_rounded,
              label: 'Reports',
            ),
            const SizedBox(width: 84),
            dockItem(
              branch: _branchContacts,
              icon: Icons.groups_outlined,
              iconSel: Icons.groups_rounded,
              label: 'Contacts',
            ),
            dockItem(
              branch: _branchVoice,
              icon: Icons.mic_none_rounded,
              iconSel: Icons.mic_rounded,
              label: 'Voice',
            ),
          ],
        ),
      ),
    );
  }
}
