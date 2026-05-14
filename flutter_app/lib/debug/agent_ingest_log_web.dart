import 'dart:convert';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

// #region agent log
/// Sends one NDJSON-equivalent payload to the Cursor debug ingest (web only).
void agentIngestLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, Object?>? data,
  String runId = 'pre-fix',
}) {
  final payload = <String, Object?>{
    'sessionId': '767544',
    'timestamp': DateTime.now().millisecondsSinceEpoch,
    'location': location,
    'message': message,
    'hypothesisId': hypothesisId,
    'runId': runId,
    'data': data ?? const <String, Object?>{},
  };
  try {
    // ignore: unawaited_futures
    html.HttpRequest.request(
      'http://127.0.0.1:7615/ingest/1a9bc12a-2d76-4412-82f6-a4a020b0949f',
      method: 'POST',
      sendData: jsonEncode(payload),
      requestHeaders: {
        'Content-Type': 'application/json',
        'X-Debug-Session-Id': '767544',
      },
    ).then((_) {}, onError: (_) {});
  } catch (_) {}
}
// #endregion agent log
