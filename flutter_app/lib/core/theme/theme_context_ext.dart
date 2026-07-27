import 'package:flutter/material.dart';

import 'hexa_colors.dart';

/// Light mode → iOS-like grouped background + white cards; dark → existing Hexa navy palette.
extension HarisreeAdaptiveTheme on BuildContext {
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;

  Color get adaptiveScaffold =>
      isDarkTheme ? HexaColors.canvas : Theme.of(this).scaffoldBackgroundColor;

  Color get adaptiveAppBarBg => isDarkTheme
      ? HexaColors.canvas
      : (Theme.of(this).appBarTheme.backgroundColor ??
          Theme.of(this).colorScheme.surface);

  /// Cards / sheets: white on light, navy card on dark.
  Color get adaptiveCard =>
      isDarkTheme ? HexaColors.surfaceCard : Colors.white;

  /// Secondary panels, chips background.
  Color get adaptiveElevated => isDarkTheme
      ? HexaColors.surfaceElevated
      : const Color(0xFFF2F2F7);
}
