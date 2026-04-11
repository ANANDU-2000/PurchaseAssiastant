import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureTokenStore {
  static const _access = 'hexa_access_token';
  static const _refresh = 'hexa_refresh_token';
  /// Plain backup on web — survives refresh reliably if IndexedDB path is cleared.
  static const _accessBk = 'hexa_access_token_bk';
  static const _refreshBk = 'hexa_refresh_token_bk';

  SecureTokenStore(this._prefs);

  final SharedPreferences? _prefs;

  static const FlutterSecureStorage _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    webOptions: WebOptions(
      dbName: 'HexaAuth',
      publicKey: 'HexaAuthKey',
    ),
  );

  Future<void> write({required String access, required String refresh}) async {
    await Future.wait([
      _s.write(key: _access, value: access),
      _s.write(key: _refresh, value: refresh),
    ]);
    if (kIsWeb) {
      final p = _prefs;
      if (p != null) {
        await p.setString(_accessBk, access);
        await p.setString(_refreshBk, refresh);
      }
    }
  }

  Future<({String? access, String? refresh})> read() async {
    var access = await _s.read(key: _access);
    var refresh = await _s.read(key: _refresh);
    if (kIsWeb) {
      final p = _prefs;
      if (p != null) {
        access ??= p.getString(_accessBk);
        refresh ??= p.getString(_refreshBk);
      }
    }
    return (access: access, refresh: refresh);
  }

  Future<void> clear() async {
    await Future.wait([
      _s.delete(key: _access),
      _s.delete(key: _refresh),
    ]);
    final p = _prefs;
    if (p != null) {
      await p.remove(_accessBk);
      await p.remove(_refreshBk);
    }
  }
}
