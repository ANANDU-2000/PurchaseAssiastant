import 'package:flutter/material.dart';

/// Scrolls a field into view after validation (e.g. first error).
Future<void> ensureFormFieldVisible(GlobalKey key) async {
  final ctx = key.currentContext;
  if (ctx == null) return;
  await Scrollable.ensureVisible(
    ctx,
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    alignment: 0.12,
  );
}
