import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'hexa_responsive.dart';

/// Desktop (web + native): centered content with max width and horizontal padding.
class HexaWebPageFrame extends StatelessWidget {
  const HexaWebPageFrame({
    super.key,
    required this.child,
    this.maxWidth = HexaResponsive.maxContentWidth,
    this.horizontalPadding = 24,
    this.fullWidth = false,
  });

  final Widget child;
  final double maxWidth;
  final double horizontalPadding;

  /// Master-detail pages (stock list + detail) need full shell width.
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    if (fullWidth || !context.isDesktopLayout) {
      return child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 200) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final width = math.min(constraints.maxWidth, maxWidth);
        final framed = Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: child,
        );

        if (constraints.hasBoundedHeight) {
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: framed,
            ),
          );
        }

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: framed,
          ),
        );
      },
    );
  }
}
