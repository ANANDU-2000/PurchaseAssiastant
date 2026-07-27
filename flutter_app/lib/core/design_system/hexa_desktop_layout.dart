import 'package:flutter/material.dart';

import 'hexa_operational_tokens.dart';
import 'hexa_responsive.dart';

/// Master-detail split for desktop warehouse pages (≥ [kDesktopMin]).
class DesktopMasterDetailScaffold extends StatelessWidget {
  const DesktopMasterDetailScaffold({
    super.key,
    required this.list,
    required this.detail,
    this.listFlex = 5,
    this.detailFlex = 5,
    this.showDivider = true,
  });

  final Widget list;
  final Widget detail;
  final int listFlex;
  final int detailFlex;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    if (!context.isDesktopLayout) {
      return list;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: listFlex, child: list),
        if (showDivider) const VerticalDivider(width: 1, thickness: 1),
        Expanded(flex: detailFlex, child: detail),
      ],
    );
  }
}

/// Two-column card grid for owner home / reports on desktop.
class DesktopTwoColumnGrid extends StatelessWidget {
  const DesktopTwoColumnGrid({
    super.key,
    required this.children,
    this.minTileWidth = 280,
    this.spacing = 12,
    this.runSpacing = 12,
  });

  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    if (!context.isDesktopLayout || children.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: runSpacing),
            children[i],
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = (constraints.maxWidth / (minTileWidth + spacing))
            .floor()
            .clamp(1, 2);
        if (cols <= 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: runSpacing),
                children[i],
              ],
            ],
          );
        }
        final tileW = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final c in children)
              SizedBox(width: tileW, child: c),
          ],
        );
      },
    );
  }
}

/// Optional footer block for extended navigation rail (business + notifications).
class DesktopSideNavFooter extends StatelessWidget {
  const DesktopSideNavFooter({
    super.key,
    required this.businessName,
    required this.roleLabel,
    this.notificationCount = 0,
    this.onNotificationsTap,
    this.onSettingsTap,
  });

  final String businessName;
  final String roleLabel;
  final int notificationCount;
  final VoidCallback? onNotificationsTap;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 8),
          Text(
            businessName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HexaOp.cardTitle(context),
          ),
          Text(
            roleLabel,
            style: HexaOp.caption(context),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (onNotificationsTap != null)
                IconButton(
                  tooltip: 'Notifications',
                  onPressed: onNotificationsTap,
                  icon: Badge(
                    isLabelVisible: notificationCount > 0,
                    label: Text('$notificationCount'),
                    child: const Icon(Icons.notifications_outlined),
                  ),
                ),
              if (onSettingsTap != null)
                IconButton(
                  tooltip: 'Settings',
                  onPressed: onSettingsTap,
                  icon: const Icon(Icons.settings_outlined),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
