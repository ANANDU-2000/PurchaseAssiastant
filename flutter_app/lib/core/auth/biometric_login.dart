import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

const _kBioUserKey = 'biometric_login_email';

/// Stores username for biometric re-login (refresh token stays in secure storage).
class BiometricLogin {
  BiometricLogin._();

  static const _storage = FlutterSecureStorage();
  static final _auth = LocalAuthentication();

  static Future<bool> isDeviceSupported() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;
    try {
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  /// Device supports biometrics and the user can authenticate with them.
  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await isDeviceSupported() && await canCheckBiometrics();
    } catch (_) {
      return false;
    }
  }

  static Future<String?> savedEmail() => _storage.read(key: _kBioUserKey);

  static Future<void> saveEmail(String email) async {
    await _storage.write(key: _kBioUserKey, value: email.trim().toLowerCase());
  }

  static Future<void> clear() => _storage.delete(key: _kBioUserKey);

  static Future<bool> authenticate({String reason = 'Sign in to Harisree'}) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
