import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';

/// Extra bottom gap for iOS keyboard **accessory** (Prev/Next/Done) — not always
/// folded into [MediaQuery.viewInsets]. Tune after device measurement; see
/// `context/form_ux/IOS_KEYBOARD_OVERLAY_AUDIT.md`.
const double kMobileFormKeyboardAccessoryAllowance = 36;

bool get _isCupertinoFamily =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// Extra scroll padding below the focused field (IME + optional iOS accessory).
EdgeInsets formFieldScrollPaddingForContext(
  BuildContext context, {
  required double reserveBelowField,
}) {
  final ime = MediaQuery.viewInsetsOf(context).bottom;
  final accessory = _isCupertinoFamily ? kMobileFormKeyboardAccessoryAllowance : 0.0;
  return EdgeInsets.only(bottom: ime + reserveBelowField + accessory);
}

/// Registers [FocusNode] so when it gains focus the field scrolls into view
/// inside the nearest [Scrollable] (wizard body, sheets, etc.).
void bindFocusNodeScrollIntoView(FocusNode node) {
  node.addListener(() {
    if (!node.hasFocus) return;
    final ctx = node.context;
    if (ctx == null || !ctx.mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ctx.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
        ),
      );
    });
  });
}

Future<void> ensureFormFieldVisible(
  GlobalKey key, {
  double alignment = 0.12,
}) async {
  final ctx = key.currentContext;
  if (ctx == null) return;
  await Scrollable.ensureVisible(
    ctx,
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    alignment: alignment,
  );
}
