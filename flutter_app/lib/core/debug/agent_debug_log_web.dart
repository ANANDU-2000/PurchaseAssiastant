import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

void agentDebugLogImpl({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'pre-fix',
}) {
  // #region agent log
  try {
    final payload = <String, Object?>{
      'sessionId': '2a33ed',
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    html.HttpRequest.request(
      'http://127.0.0.1:7388/ingest/8ef5481a-9163-494f-9f26-ab47a81c6701',
      method: 'POST',
      requestHeaders: {
        'Content-Type': 'application/json',
        'X-Debug-Session-Id': '2a33ed',
      },
      sendData: jsonEncode(payload),
    ).catchError((_) => html.HttpRequest());
  } catch (_) {}
  // #endregion
}
