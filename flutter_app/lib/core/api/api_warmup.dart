import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show VoidCallback;

import 'hexa_api.dart';

/// Cold PaaS warm-up (`/health/live`) and optional periodic ping.
class ApiWarmupService {
  ApiWarmupService._();

  static Timer? _keepAlive;

  static const _attemptTimeout = Duration(seconds: 8);
  static const _retryDelay = Duration(seconds: 3);
  static const _maxAttempts = 10;

  /// Call before authenticated traffic: probes `/health/live` then `/health/ready`.
  /// Retries help sleepy PaaS cold starts (Render can take 30–90s); **stops immediately**
  /// on connection refused.
  static Future<void> pingHealth(
    HexaApi api, {
    VoidCallback? onSlow,
    VoidCallback? onUnreachable,
  }) async {
    final slow = Timer(const Duration(seconds: 3), () => onSlow?.call());
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      try {
        await _pingLiveWithRetry(api);
        await api.healthReady().timeout(const Duration(seconds: 15));
        slow.cancel();
        return;
      } catch (e) {
        if (_isUnreachableHost(e)) {
          slow.cancel();
          onUnreachable?.call();
          return;
        }
        if (attempt < _maxAttempts - 1) {
          await Future<void>.delayed(Duration(seconds: attempt + 2));
        }
      }
    }
    slow.cancel();
  }

  static Future<void> _pingLiveWithRetry(HexaApi api) async {
    try {
      await api.healthLive().timeout(_attemptTimeout);
    } on TimeoutException {
      await Future<void>.delayed(_retryDelay);
      await api.healthLive().timeout(_attemptTimeout);
    }
  }

  static bool _isUnreachableHost(Object e) {
    if (e is DioException) {
      return e.type == DioExceptionType.connectionError;
    }
    return false;
  }

  /// Keeps sleepy hosts warmer during a session (battery/network tradeoff).
  static void startPeriodicHealth(HexaApi api) {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(minutes: 10), (_) {
      unawaited(() async {
        try {
          await api.healthLive().timeout(const Duration(seconds: 12));
        } catch (_) {}
      }());
    });
  }

  static void stopPeriodicHealth() {
    _keepAlive?.cancel();
    _keepAlive = null;
  }
}
