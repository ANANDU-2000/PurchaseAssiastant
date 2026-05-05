import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;

import 'hexa_api.dart';

/// Cold PaaS warm-up (`/health/ready` + `/health`) and optional periodic ping.
class ApiWarmupService {
  ApiWarmupService._();

  static Timer? _keepAlive;

  /// Call before authenticated traffic: probes `/health/ready` (DB) then `/health`.
  static Future<void> pingHealth(HexaApi api, {VoidCallback? onSlow}) async {
    final slow = Timer(const Duration(seconds: 3), () => onSlow?.call());
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await api.healthReady().timeout(const Duration(seconds: 8));
        slow.cancel();
        return;
      } catch (_) {
        try {
          await api.health().timeout(const Duration(seconds: 8));
          slow.cancel();
          return;
        } catch (_) {
          await Future<void>.delayed(Duration(seconds: attempt + 1));
        }
      }
    }
    slow.cancel();
  }

  /// Keeps sleepy hosts warmer during a session (battery/network tradeoff).
  static void startPeriodicHealth(HexaApi api) {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(() async {
        try {
          await api.healthReady().timeout(const Duration(seconds: 12));
        } catch (_) {
          try {
            await api.health().timeout(const Duration(seconds: 12));
          } catch (_) {}
        }
      }());
    });
  }

  static void stopPeriodicHealth() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }
}
