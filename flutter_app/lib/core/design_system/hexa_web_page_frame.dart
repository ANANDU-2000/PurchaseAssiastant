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
    // On Flutter web, framing with a tight height SizedBox has blanked desktop
    // shells when parent maxHeight was 0/odd. Prefer unconstrained child +
    // horizontal centering only.
    if (fullWidth || !context.isDesktopLayout || kIsWeb) {
      if (fullWidth || !context.isDesktopLayout) {
        return child;
      }
      final framed = Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: child,
      );
      return Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: framed,
        ),
      );
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

        if (constraints.hasBoundedHeight && constraints.maxHeight >= 1) {
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: framed,
            ),
          );
        }

        final viewportHeight = MediaQuery.sizeOf(context).height;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: viewportHeight > 0 ? viewportHeight : null,
            child: framed,
          ),
        );
      },
    );
  }
}
