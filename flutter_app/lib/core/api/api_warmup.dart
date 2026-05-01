import 'dart:async';

import 'hexa_api.dart';

/// Cold PaaS warm-up (/health) and optional periodic ping.
class ApiWarmupService {
  ApiWarmupService._();

  static Timer? _keepAlive;

  /// Call before authenticated traffic: 3 attempts, backoff 1s / 2s after failures.
  static Future<void> pingHealth(HexaApi api) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await api.health().timeout(const Duration(seconds: 8));
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    }
  }

  /// Keeps sleepy hosts warmer during a session (battery/network tradeoff).
  static void startPeriodicHealth(HexaApi api) {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(() async {
        try {
          await api.health().timeout(const Duration(seconds: 12));
        } catch (_) {}
      }());
    });
  }

  static void stopPeriodicHealth() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }
}
