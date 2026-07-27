import 'package:flutter/foundation.dart';

import '../auth/auth_error_messages.dart';

/// Short, production-safe copy for SnackBars, dialogs, and inline form errors.
/// Never exposes Dio internals, HTTP status codes, or stack traces.
String userFacingError(Object error, {bool forAssistant = false}) {
  return friendlyApiError(error, forAssistant: forAssistant);
}

/// Logs the underlying failure for developers (debug mode only).
/// Use for Crashlytics/Sentry wiring later; keep UI on [userFacingError] only.
void logSilencedApiError(Object error, [StackTrace? stackTrace]) {
  if (!kDebugMode) return;
  debugPrint('[API] $error');
  if (stackTrace != null) {
    debugPrint('$stackTrace');
  }
}
