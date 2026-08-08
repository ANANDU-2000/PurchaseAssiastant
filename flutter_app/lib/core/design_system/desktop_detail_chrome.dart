import 'package:flutter/material.dart';

import '../theme/hexa_colors.dart';
import 'hexa_ds_tokens.dart';

/// One entry in a pane-anchored "More" menu (not a screen-level overlay).
class DesktopMoreAction {
  const DesktopMoreAction({
    required this.label,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;
}

/// Primary action row + optional pane-anchored More menu for desktop detail panes.
///
/// Reuse for Stock, Purchases, Reports, Staff — keep primary CTAs ≤2 and put
/// the rest behind [moreActions].
class DesktopActionBar extends StatelessWidget {
  const DesktopActionBar({
    super.key,
    required this.primaryActions,
    this.moreActions = const [],
    this.moreTooltip = 'More',
  });

  final List<Widget> primaryActions;
  final List<DesktopMoreAction> moreActions;
  final String moreTooltip;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...primaryActions,
        if (moreActions.isNotEmpty)
          PopupMenuButton<int>(
            tooltip: moreTooltip,
            offset: const Offset(0, 40),
            onSelected: (i) {
              if (i >= 0 && i < moreActions.length) {
                moreActions[i].onSelected();
              }
            },
            itemBuilder: (context) => [
              for (var i = 0; i < moreActions.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  child: Row(
                    children: [
                      if (moreActions[i].icon != null) ...[
                        Icon(moreActions[i].icon, size: 18),
                        const SizedBox(width: 10),
                      ],
                      Expanded(child: Text(moreActions[i].label)),
                    ],
                  ),
                ),
            ],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: HexaColors.slate700.withValues(alpha: 0.35),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.more_horiz, size: 18),
                  SizedBox(width: 6),
                  Text('More', style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Shared chrome for desktop master-detail right panes.
///
/// Layout: header → stats → actions → dedicated scrollable [body] section
/// (e.g. recent activity) that does not share the stats' scroll viewport.
class DesktopDetailPaneScaffold extends StatelessWidget {
  const DesktopDetailPaneScaffold({
    super.key,
    required this.header,
    this.stats,
    this.actions,
    this.body,
    this.bodyTitle,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget header;
  final Widget? stats;
  final Widget? actions;
  final Widget? body;
  final String? bodyTitle;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? HexaColors.panelWarm;
    return ColoredBox(
      color: bg,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            if (stats != null) ...[
              const SizedBox(height: 12),
              stats!,
            ],
            if (actions != null) ...[
              const SizedBox(height: 16),
              actions!,
            ],
            if (body != null) ...[
              const SizedBox(height: 20),
              if (bodyTitle != null) ...[
                Text(bodyTitle!, style: HexaDsType.label(12)),
                const SizedBox(height: 8),
              ],
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: HexaColors.slate700.withValues(alpha: 0.08),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: body!,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
