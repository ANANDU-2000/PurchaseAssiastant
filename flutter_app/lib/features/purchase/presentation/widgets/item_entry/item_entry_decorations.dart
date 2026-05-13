import 'package:flutter/material.dart';

import '../../../../../core/theme/hexa_colors.dart';

/// High-contrast outline fields for purchase item entry (old-trader / outdoor readability).
InputDecoration itemEntryFieldDecoration(
  ThemeData theme, {
  required String label,
  String? prefixText,
  String? errorText,
  bool fullPage = false,
}) {
  final pad = fullPage
      ? const EdgeInsets.symmetric(horizontal: 12, vertical: 14)
      : const EdgeInsets.symmetric(horizontal: 10, vertical: 12);
  const borderRadius = BorderRadius.all(Radius.circular(8));
  const strongGrey = Color(0xFF475569); // slate-600
  const focusWidth = 2.5;

  return InputDecoration(
    labelText: label,
    labelStyle: TextStyle(
      fontWeight: FontWeight.w800,
      fontSize: fullPage ? 14 : 13,
      color: const Color(0xFF0F172A),
    ),
    prefixText: prefixText,
    errorText: errorText,
    errorMaxLines: 2,
    isDense: false,
    border: const OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: strongGrey, width: 1.75),
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: strongGrey, width: 1.75),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide:
          BorderSide(color: theme.colorScheme.primary, width: focusWidth),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: Colors.red[800]!, width: 1.75),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: Colors.red[900]!, width: focusWidth),
    ),
    filled: true,
    fillColor: HexaColors.surfaceApp,
    contentPadding: pad,
  );
}
