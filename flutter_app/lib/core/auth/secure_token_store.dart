import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureTokenStore {
  static const _access = 'hexa_access_token';
  static const _refresh = 'hexa_refresh_token';

  final FlutterSecureStorage _s = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<void> write({required String access, required String refresh}) async {
    await Future.wait([
      _s.write(key: _access, value: access),
      _s.write(key: _refresh, value: refresh),
    ]);
  }

  Future<({String? access, String? refresh})> read() async {
    final access = await _s.read(key: _access);
    final refresh = await _s.read(key: _refresh);
    return (access: access, refresh: refresh);
  }

  Future<void> clear() async {
    await Future.wait([
      _s.delete(key: _access),
      _s.delete(key: _refresh),
    ]);
  }
}
