import 'package:dio/dio.dart';

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
      'sessionId': '9910c7',
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    Dio()
        .post<void>(
          'http://127.0.0.1:7388/ingest/8ef5481a-9163-494f-9f26-ab47a81c6701',
          data: payload,
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'X-Debug-Session-Id': '9910c7',
            },
          ),
        )
        .catchError((Object _) => Response<void>(requestOptions: RequestOptions()));
  } catch (_) {}
  // #endregion
}
