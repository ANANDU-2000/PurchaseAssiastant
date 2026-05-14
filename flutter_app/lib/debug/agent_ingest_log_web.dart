// Diagnostic ingest removed — was targeting localhost:7615 in production.
void agentIngestLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, Object?>? data,
  String runId = 'pre-fix',
}) {
  // no-op: debug-only endpoint removed from production build.
}
