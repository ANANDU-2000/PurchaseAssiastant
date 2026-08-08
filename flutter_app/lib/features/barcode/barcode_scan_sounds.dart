import 'package:flutter/services.dart';

/// Scan acknowledgement sounds (no extra packages).
class BarcodeScanSounds {
  BarcodeScanSounds._();

  /// Known item / cache hit / successful decode ack.
  static Future<void> playSuccess() async {
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {}
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Not found, network, or permission failure.
  static Future<void> playFailure() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
