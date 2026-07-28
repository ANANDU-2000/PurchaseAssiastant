import 'package:flutter/material.dart';

import 'hexa_responsive.dart';

/// Page width framing helper.
///
/// Horizontal max-width belongs on the page ([HexaResponsiveCenter], etc.).
/// Do **not** wrap scrollables (e.g. [CustomScrollView] on Home) in
/// Align + max-width-only constraints — on Flutter web that leaves height
/// unbounded and paints a blank desktop shell (≥1024px).
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
    return child;
  }
}
