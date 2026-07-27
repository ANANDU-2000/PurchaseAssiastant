import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_system/hexa_responsive.dart';

/// Centers page content on wide screens with a max readable width.
///
/// On narrow widths (< [minWidth]), [child] is full width. Use [fullWidth] for
/// pages that already implement their own master-detail layout on desktop.
class DesktopPageShell extends StatelessWidget {
  const DesktopPageShell({
    super.key,
    required this.child,
    this.maxContentWidth = 900,
    this.minWidth = kDesktopMin,
    this.padding,
    this.fullWidth = false,
  });

  final Widget child;
  final double maxContentWidth;
  final double minWidth;
  final EdgeInsetsGeometry? padding;

  /// When true, never constrain — for stock/purchase/reports split layouts.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (fullWidth) return child;

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth) {
          return content;
        }

        final width = math.min(constraints.maxWidth, maxContentWidth);

        // Align-only wrapping gives scrollables / Expanded unbounded height → blank UI.
        if (constraints.hasBoundedHeight) {
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: content,
            ),
          );
        }

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: content,
          ),
        );
      },
    );
  }
}
