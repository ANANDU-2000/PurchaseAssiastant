import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../config/app_config.dart';
import 'current_route.dart';

/// Fire-and-forget production error sink.
///
/// Sends sanitised (no PII) exception + stack + route to the backend
/// `POST /v1/client-errors` endpoint for every error NOT classified as benign.
/// Throttled client-side (≥2 s between sends) and server-side (≥0.5 s).
class HexaErrorSink {
  HexaErrorSink._();

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: AppConfig.resolvedApiBaseUrl,
    connectTimeout: const Duration(seconds: 5),
    sendTimeout: const Duration(seconds: 5),
    headers: {'Content-Type': 'application/json'},
  ));

  static DateTime _lastSend = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _minInterval = Duration(seconds: 2);

  /// True while a send is in flight (prevents overlapping fire-and-forget calls).
  static bool _inFlight = false;

  /// Fire-and-forget: POST sanitised error to the backend.
  /// Never throws — failures are silently ignored (the error already happened).
  static void report(Object error, StackTrace stack) {
    final now = DateTime.now();
    if (now.difference(_lastSend) < _minInterval) return;
    if (_inFlight) return;
    _lastSend = now;

    unawaited(_send(error, stack));
  }

  static Future<void> _send(Object error, StackTrace stack) async {
    _inFlight = true;
    try {
      final type = _truncate(error.runtimeType.toString(), 120);
      final message = _sanitiseMessage(error.toString());
      final stackStr = _sanitiseStack(stack.toString());
      final route = _truncate(CurrentRoute.path, 200);
      final platform = _detectPlatform();

      await _dio.post<void>(
        '/v1/client-errors',
        data: {
          'error_type': type,
          'message': message,
          'stack': stackStr,
          'route': route,
          'platform': platform,
          'app_version': AppConfig.packageVersion,
          'is_debug': kDebugMode,
        },
        options: Options(
          headers: {'x-requested-with': 'harisree-app'},
          extra: {'no_auth': true},
        ),
      );
    } catch (_) {
      // Sink must never throw.
    } finally {
      _inFlight = false;
    }
  }

  /// Truncate string to [maxLen] chars to satisfy backend Pydantic max_length.
  static String _truncate(String s, int maxLen) {
    return s.length <= maxLen ? s : '${s.substring(0, maxLen)}…';
  }

  /// Strip PII-like content: email addresses, phone numbers, JWT-like tokens.
  static String _sanitiseMessage(String raw) {
    var s = raw;
    // Email addresses → [redacted-email]
    s = s.replaceAll(RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), '[redacted-email]');
    // Phone numbers (10+ digits) → [redacted-phone]
    s = s.replaceAll(RegExp(r'\b\d{10,}\b'), '[redacted-phone]');
    // Bearer / JWT tokens → [redacted-token]
    s = s.replaceAll(RegExp(r'Bearer\s+[A-Za-z0-9._-]+'), 'Bearer [redacted-token]');
    s = s.replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'), '[redacted-jwt]');
    return s.length > 500 ? '${s.substring(0, 500)}…' : s;
  }

  /// Truncate stack and strip file-system absolute paths.
  static String _sanitiseStack(String raw) {
    // Remove C:\Users\... or /home/... style absolute paths — keep only relative.
    var s = raw.replaceAll(RegExp(r'[A-Z]:\\[^\s]+\\'), '');
    s = s.replaceAll(RegExp(r'/home/[^\s]+/'), '');
    return s.length > 2000 ? '${s.substring(0, 2000)}…' : s;
  }

  static String _detectPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isMacOS) return 'macos';
      if (Platform.isWindows) return 'windows';
      if (Platform.isLinux) return 'linux';
    } catch (_) {}
    return 'unknown';
  }

  /// Debug-only: trigger a test exception to verify the sink fires.
  /// Call from settings page or debug console. Throws immediately so the
  /// error handler catches it and sends it to the backend.
  static void triggerTestException() {
    if (!kDebugMode) return;
    throw StateError(
      '[HexaErrorSink test] Deliberate exception to verify error sink. '
      'Route: ${CurrentRoute.path}',
    );
  }
}
