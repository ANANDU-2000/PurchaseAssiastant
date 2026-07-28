import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../debug/agent_debug_log.dart';
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
    // Flutter web: never wrap scrollables in Align+maxWidth-only ConstrainedBox —
    // that leaves height unbounded and blanks /home (CustomScrollView). Pages already
    // use [HexaResponsiveCenter] for horizontal max width.
    if (fullWidth || !context.isDesktopLayout || kIsWeb) {
      return child;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // #region agent log
        agentDebugLog(
          hypothesisId: 'H2',
          location: 'hexa_web_page_frame.dart:build',
          message: 'desktop frame constraints',
          data: {
            'maxW': constraints.maxWidth,
            'maxH': constraints.maxHeight,
            'boundedH': constraints.hasBoundedHeight,
            'mqH': MediaQuery.sizeOf(context).height,
            'mqW': MediaQuery.sizeOf(context).width,
          },
        );
        // #endregion
        if (!constraints.hasBoundedWidth || constraints.maxWidth < 200) {
          return child;
        }
        if (!constraints.hasBoundedHeight || constraints.maxHeight < 1) {
          return child;
        }

        final width = math.min(constraints.maxWidth, maxWidth);
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: constraints.maxHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
