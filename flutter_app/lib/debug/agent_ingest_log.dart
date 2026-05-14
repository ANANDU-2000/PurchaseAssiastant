import 'agent_ingest_log_stub.dart'
    if (dart.library.html) 'agent_ingest_log_web.dart' as ingest;

// #region agent log
void agentIngestLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, Object?>? data,
  String runId = 'pre-fix',
}) =>
    ingest.agentIngestLog(
      location: location,
      message: message,
      hypothesisId: hypothesisId,
      data: data,
      runId: runId,
    );
// #endregion agent log
