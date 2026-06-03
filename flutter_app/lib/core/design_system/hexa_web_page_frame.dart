import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'hexa_responsive.dart';

/// Web desktop: centered content with max width and horizontal padding.
class HexaWebPageFrame extends StatelessWidget {
  const HexaWebPageFrame({
    super.key,
    required this.child,
    this.maxWidth = 800,
    this.horizontalPadding = 24,
  });

  final Widget child;
  final double maxWidth;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !context.isDesktopLayout) {
      return child;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: child,
        ),
      ),
    );
  }
}
