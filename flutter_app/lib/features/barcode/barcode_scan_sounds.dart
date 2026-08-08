import 'package:flutter/services.dart';

/// Scan acknowledgement sounds (no extra packages).
class BarcodeScanSounds {
  BarcodeScanSounds._();

  /// Fired the moment a barcode is decoded (before lookup).
  static Future<void> playDecode({bool enabled = true}) async {
    if (!enabled) {
      try {
        await HapticFeedback.selectionClick();
      } catch (_) {}
      return;
    }
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Known item / cache hit.
  static Future<void> playSuccess({bool enabled = true}) async {
    if (!enabled) {
      try {
        await HapticFeedback.mediumImpact();
      } catch (_) {}
      return;
    }
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Not found, network, or permission failure.
  static Future<void> playFailure({bool enabled = true}) async {
    if (!enabled) {
      try {
        await HapticFeedback.lightImpact();
      } catch (_) {}
      return;
    }
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
