/// Debug-mode NDJSON ingest (web implementation posts to local collector).
void agentIngestLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, Object?>? data,
  String runId = 'pre-fix',
}) {}
