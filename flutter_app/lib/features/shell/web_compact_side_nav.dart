import 'package:flutter/material.dart';

import '../../core/design_system/hexa_responsive.dart';
import '../../core/theme/hexa_colors.dart';

/// Fixed-width icon side nav for Flutter **web**.
///
/// [NavigationRail] has repeatedly blanked the shell body on wide viewports
/// (unconstrained / overflow width → [Expanded] content at 0×). This widget
/// never grows past [kShellCompactRailWidth].
class WebCompactSideNav extends StatelessWidget {
  const WebCompactSideNav({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    this.footer,
  });

  final int selectedIndex;
  final List<WebCompactSideNavItem> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: kShellCompactRailWidth,
          child: Column(
            children: [
              const SizedBox(height: 8),
              for (var i = 0; i < destinations.length; i++)
                _NavIconButton(
                  item: destinations[i],
                  selected: selectedIndex == i,
                  onTap: () => onDestinationSelected(i),
                ),
              const Spacer(),
              if (footer != null) footer!,
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class WebCompactSideNavItem {
  const WebCompactSideNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;
}

class _NavIconButton extends StatelessWidget {
  const _NavIconButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final WebCompactSideNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = Icon(
      selected ? item.selectedIcon : item.icon,
      color: selected ? HexaColors.brandPrimary : cs.onSurfaceVariant,
    );
    return Tooltip(
      message: item.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: kShellCompactRailWidth,
          height: 56,
          child: Center(
            child: item.badgeCount > 0
                ? Badge(
                    label: Text(
                      item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                    ),
                    child: icon,
                  )
                : icon,
          ),
        ),
      ),
    );
  }
}
