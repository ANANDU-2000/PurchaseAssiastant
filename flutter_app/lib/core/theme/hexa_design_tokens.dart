import 'package:flutter/material.dart';

/// POS-style density targets (see product UX audit).
abstract final class HexaDesignTokens {
  static const double screenPadding = 16;
  static const double fieldGap = 12;
  /// Section vertical rhythm — 8px grid (2 × 8).
  static const double sectionGap = 16;
  static const double sectionGapLoose = 24;
  static const double sectionGapXL = 32;

  /// Primary screen title (toolbar / section headers).
  static const double titleApp = 18;

  /// Field labels, chips, helper copy.
  static const double label = 14;

  /// Input text (match minimum tap target readability).
  static const double input = 16;

  /// Suggestion list under typeahead fields.
  static const double suggestionsMaxHeight = 250;

  /// Primary CTA minimum height.
  static const double buttonHeight = 48;

  static EdgeInsets get pagePadding =>
      const EdgeInsets.fromLTRB(screenPadding, 8, screenPadding, 16);
}
