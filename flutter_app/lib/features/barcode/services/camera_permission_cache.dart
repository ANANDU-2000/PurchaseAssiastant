/// Session-scoped camera permission hints (complements SharedPreferences).
class CameraPermissionCache {
  CameraPermissionCache._();

  static final CameraPermissionCache instance = CameraPermissionCache._();

  bool grantedThisSession = false;
  bool deniedThisSession = false;
  bool? persistedGranted;

  void markGranted() {
    grantedThisSession = true;
    deniedThisSession = false;
    persistedGranted = true;
  }

  void markDenied({bool permanent = false}) {
    if (permanent) deniedThisSession = true;
    grantedThisSession = false;
  }

  bool get canAutoStartCamera =>
      grantedThisSession || persistedGranted == true;

  void resetSession() {
    grantedThisSession = false;
    deniedThisSession = false;
  }
}
