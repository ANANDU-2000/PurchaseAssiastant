import 'dart:convert';

/// True when JWT `exp` is in the past (or within [skew] of now).
bool isAccessTokenExpiredOrNearExpiry(
  String? accessToken, {
  Duration skew = const Duration(seconds: 90),
}) {
  if (accessToken == null || accessToken.trim().isEmpty) return true;
  final parts = accessToken.split('.');
  if (parts.length < 2) return false;
  try {
    var payload = parts[1];
    final mod = payload.length % 4;
    if (mod > 0) payload += '=' * (4 - mod);
    final decoded = utf8.decode(base64Url.decode(payload));
    final map = jsonDecode(decoded);
    if (map is! Map<String, dynamic>) return false;
    final exp = map['exp'];
    if (exp is! num) return false;
    final expMs = (exp * 1000).floor();
    return DateTime.now().millisecondsSinceEpoch >= expMs - skew.inMilliseconds;
  } catch (_) {
    return false;
  }
}
