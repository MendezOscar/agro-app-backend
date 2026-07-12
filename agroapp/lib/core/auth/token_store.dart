import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persiste tokens JWT y datos de sesión de forma segura.
class TokenStore {
  static const _storage = FlutterSecureStorage();
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kOrg = 'org_id';
  static const _kUser = 'user_id';

  Future<void> save({
    required String access,
    required String refresh,
    required String orgId,
    required String userId,
  }) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
    await _storage.write(key: _kOrg, value: orgId);
    await _storage.write(key: _kUser, value: userId);
  }

  Future<String?> get accessToken => _storage.read(key: _kAccess);
  Future<String?> get refreshToken => _storage.read(key: _kRefresh);
  Future<String?> get orgId => _storage.read(key: _kOrg);
  Future<String?> get userId => _storage.read(key: _kUser);

  Future<void> updateAccess(String access, String refresh) async {
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> clear() => _storage.deleteAll();
}
