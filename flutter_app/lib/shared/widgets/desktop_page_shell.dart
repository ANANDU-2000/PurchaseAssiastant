import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/design_system/hexa_responsive.dart';

/// Constrains page content on wide screens with a max readable width.
///
/// On narrow widths (< [minWidth]), [child] is full width. Use [fullWidth] for
/// pages that already implement their own master-detail layout on desktop.
///
/// Desktop (≥ [kDesktopMin]): content is **left-aligned** with the sidebar so
/// unused space sits on the right (no center-float blank gutters on 1600/1920).
class DesktopPageShell extends StatelessWidget {
  const DesktopPageShell({
    super.key,
    required this.child,
    this.maxContentWidth = HexaResponsive.maxFormWidth,
    this.minWidth = kDesktopMin,
    this.padding,
    this.fullWidth = false,
  });

  final Widget child;
  final double maxContentWidth;
  final double minWidth;
  final EdgeInsetsGeometry? padding;

  /// When true, never constrain width — for stock/purchase/reports split layouts.
  /// Still applies a height bound when the parent gives unbounded height so
  /// scrollables / Expanded do not paint a blank CanvasKit surface.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (fullWidth) {
      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedHeight) return child;
          final h = MediaQuery.sizeOf(context).height;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: h),
            child: SizedBox(height: h, child: child),
          );
        },
      );
    }

    Widget content = child;
    if (padding != null) {
      content = Padding(padding: padding!, child: content);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < minWidth) {
          if (constraints.hasBoundedHeight) return content;
          final h = MediaQuery.sizeOf(context).height;
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: h),
            child: SizedBox(height: h, child: content),
          );
        }

        final windowW = MediaQuery.sizeOf(context).width;
        final resolved =
            HexaResponsive.resolveDesktopMax(windowW, maxContentWidth);
        final width = math.min(constraints.maxWidth, resolved);
        // Desktop: flush with sidebar (topLeft). Below desktop this branch is
        // not used (maxWidth < minWidth returns above).
        const align = Alignment.topLeft;

        // Align-only wrapping gives scrollables / Expanded unbounded height → blank UI.
        if (constraints.hasBoundedHeight) {
          return Align(
            alignment: align,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: content,
            ),
          );
        }

        final h = MediaQuery.sizeOf(context).height;
        return Align(
          alignment: align,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: h),
            child: SizedBox(
              width: width,
              height: h,
              child: content,
            ),
          ),
        );
      },
    );
  }
}
