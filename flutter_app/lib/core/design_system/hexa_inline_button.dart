import 'package:flutter/material.dart';

import '../theme/hexa_colors.dart';
import 'hexa_responsive.dart';

/// Full-width card/banner buttons with safe height + padding (avoids clipped labels on web).
abstract final class HexaInlineButton {
  static const double height = HexaResponsive.minTouchTarget;

  static TextStyle? _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            height: 1.25,
          );

  static ButtonStyle filledStyle(BuildContext context) =>
      FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, height),
        fixedSize: const Size(double.infinity, height),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _labelStyle(context),
      );

  static ButtonStyle outlinedStyle(
    BuildContext context, {
    Color? foreground,
  }) =>
      OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, height),
        fixedSize: const Size(double.infinity, height),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _labelStyle(context),
        foregroundColor: foreground,
      );

  static ButtonStyle chipStyle(BuildContext context) => OutlinedButton.styleFrom(
        minimumSize: const Size(0, height),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _labelStyle(context)?.copyWith(fontSize: 14),
      );

  static ButtonStyle primaryBarStyle(BuildContext context) =>
      FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        fixedSize: const Size(double.infinity, 52),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: _labelStyle(context),
      );

  static Widget label(String text) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      );

  static Widget fullWidth({
    required BuildContext context,
    required String label,
    required VoidCallback? onPressed,
    bool filled = true,
    bool destructive = false,
  }) {
    final text = HexaInlineButton.label(label);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: filled
          ? FilledButton(
              onPressed: onPressed,
              style: filledStyle(context),
              child: text,
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: outlinedStyle(
                context,
                foreground: destructive ? HexaColors.loss : null,
              ),
              child: text,
            ),
    );
  }
}
