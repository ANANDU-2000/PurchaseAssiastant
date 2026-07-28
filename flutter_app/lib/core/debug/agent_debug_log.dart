import 'agent_debug_log_stub.dart'
    if (dart.library.html) 'agent_debug_log_web.dart' as impl;

/// Session debug ingest (Cursor debug mode). Best-effort; never throws.
void agentDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'pre-fix',
}) {
  // #region agent log
  impl.agentDebugLogImpl(
    hypothesisId: hypothesisId,
    location: location,
    message: message,
    data: data,
    runId: runId,
  );
  // #endregion
}
