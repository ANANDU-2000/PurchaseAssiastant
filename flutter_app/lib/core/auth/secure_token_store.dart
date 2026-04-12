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

  /// Web: do **not** use [FlutterSecureStorage]. Its web implementation relies on
  /// Web Crypto / IndexedDB paths that can throw [OperationError] in some browser
  /// contexts. Tokens on web are stored only in [SharedPreferences] (localStorage).
  Future<void> write({required String access, required String refresh}) async {
    if (kIsWeb) {
      final p = _prefs;
      if (p == null) return;
      await p.setString(_accessBk, access);
      await p.setString(_refreshBk, refresh);
      return;
    }
    await Future.wait([
      _s.write(key: _access, value: access),
      _s.write(key: _refresh, value: refresh),
    ]);
  }

  Future<({String? access, String? refresh})> read() async {
    if (kIsWeb) {
      final p = _prefs;
      if (p == null) return (access: null, refresh: null);
      return (
        access: p.getString(_accessBk),
        refresh: p.getString(_refreshBk),
      );
    }
    final access = await _s.read(key: _access);
    final refresh = await _s.read(key: _refresh);
    return (access: access, refresh: refresh);
  }

  Future<void> clear() async {
    if (kIsWeb) {
      final p = _prefs;
      if (p != null) {
        await p.remove(_accessBk);
        await p.remove(_refreshBk);
      }
      return;
    }
    await Future.wait([
      _s.delete(key: _access),
      _s.delete(key: _refresh),
    ]);
  }
}
