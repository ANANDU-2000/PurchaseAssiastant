import 'package:shared_preferences/shared_preferences.dart';

/// Singleton accessor for [SharedPreferences].
///
/// Eliminates repeated `SharedPreferences.getInstance()` calls across the
/// codebase. Must be initialised once during app bootstrap before any
/// consumer reads or writes prefs.
class PrefsHelper {
  PrefsHelper._();

  static SharedPreferences? _instance;

  /// Call once during bootstrap (e.g. in `main.dart`) after
  /// `SharedPreferences.getInstance()` resolves.
  static void init(SharedPreferences prefs) {
    _instance = prefs;
  }

  /// Returns the cached [SharedPreferences] instance.
  ///
  /// Throws if [init] has not been called yet.
  static SharedPreferences get prefs {
    final p = _instance;
    if (p == null) {
      throw StateError(
        'PrefsHelper.prefs accessed before init(). '
        'Call PrefsHelper.init(prefs) during app bootstrap.',
      );
    }
    return p;
  }
}
