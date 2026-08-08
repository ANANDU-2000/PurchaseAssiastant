import 'package:flutter/material.dart';

import '../../core/design_system/hexa_responsive.dart';
import '../../core/theme/hexa_colors.dart';

/// Fixed-width side nav for Flutter **web**.
///
/// [NavigationRail] has repeatedly blanked the shell body on wide viewports
/// (unconstrained / overflow width → [Expanded] content at 0×). This widget
/// never grows past a hard-capped width ([kShellCompactRailWidth] or
/// [kShellLabeledRailWidth]).
///
/// At ≥ [kDesktopMin] shows icon + label; below that, icon-only with tooltip.
class WebCompactSideNav extends StatelessWidget {
  const WebCompactSideNav({
    super.key,
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    this.footer,
    this.showLabels = false,
  });

  final int selectedIndex;
  final List<WebCompactSideNavItem> destinations;
  final ValueChanged<int> onDestinationSelected;
  final Widget? footer;

  /// When true, render icon + label at [kShellLabeledRailWidth].
  final bool showLabels;

  double get _width =>
      showLabels ? kShellLabeledRailWidth : kShellCompactRailWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: _width,
          child: Column(
            children: [
              const SizedBox(height: 8),
              for (var i = 0; i < destinations.length; i++)
                _NavIconButton(
                  item: destinations[i],
                  selected: selectedIndex == i,
                  showLabel: showLabels,
                  width: _width,
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
    required this.showLabel,
    required this.width,
    required this.onTap,
  });

  final WebCompactSideNavItem item;
  final bool selected;
  final bool showLabel;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? HexaColors.brandPrimary : cs.onSurfaceVariant;
    final icon = Icon(
      selected ? item.selectedIcon : item.icon,
      color: color,
    );
    final iconChild = item.badgeCount > 0
        ? Badge(
            label: Text(
              item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
            ),
            child: icon,
          )
        : icon;

    final content = showLabel
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                iconChild,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          )
        : Center(child: iconChild);

    final button = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: 56,
        child: content,
      ),
    );

    if (showLabel) return button;
    return Tooltip(message: item.label, child: button);
  }
}
