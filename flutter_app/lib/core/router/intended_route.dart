import 'package:shared_preferences/shared_preferences.dart';

/// Persisted deep link restored after idle JWT logout → re-login / session restore.
const kIntendedProtectedRouteKey = 'hexa_intended_protected_route';

bool isRestorableProtectedPath(String loc) {
  final path = loc.trim();
  if (path.isEmpty || path == '/') return false;
  if (path == '/splash' ||
      path == '/login' ||
      path == '/signup' ||
      path == '/get-started' ||
      path.startsWith('/forgot-password') ||
      path.startsWith('/reset-password') ||
      path.startsWith('/scan/') ||
      path.startsWith('/item/')) {
    return false;
  }
  return path.startsWith('/');
}

/// Remember the last in-app route so auth bounce can restore it.
void saveIntendedProtectedRoute(SharedPreferences prefs, String location) {
  final loc = location.trim();
  if (!isRestorableProtectedPath(loc.split('?').first)) return;
  // Cap length — avoid storing huge query blobs.
  final clipped = loc.length > 512 ? loc.substring(0, 512) : loc;
  prefs.setString(kIntendedProtectedRouteKey, clipped);
}

String? peekIntendedProtectedRoute(SharedPreferences prefs) {
  final raw = prefs.getString(kIntendedProtectedRouteKey)?.trim();
  if (raw == null || raw.isEmpty) return null;
  if (!isRestorableProtectedPath(raw.split('?').first)) {
    prefs.remove(kIntendedProtectedRouteKey);
    return null;
  }
  return raw;
}

/// Read and clear the stored deep link (one-shot after auth).
String? takeIntendedProtectedRoute(SharedPreferences prefs) {
  final v = peekIntendedProtectedRoute(prefs);
  if (v != null) {
    prefs.remove(kIntendedProtectedRouteKey);
  }
  return v;
}

void clearIntendedProtectedRoute(SharedPreferences prefs) {
  prefs.remove(kIntendedProtectedRouteKey);
}
