import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens live in the Keychain (iOS) / Keystore-backed storage (Android), never in
/// SharedPreferences. The access token is cached in memory to avoid a secure-storage
/// read on every request.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessKey = 'auth.accessToken';
  static const _refreshKey = 'auth.refreshToken';
  static const _userKey = 'auth.user';

  String? _accessTokenCache;

  Future<String?> readAccessToken() async {
    return _accessTokenCache ??= await _storage.read(key: _accessKey);
  }

  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    _accessTokenCache = accessToken;
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
  }

  /// Cached profile so the app can start (and resume a KYC draft) while offline.
  Future<void> saveUserJson(String json) => _storage.write(key: _userKey, value: json);

  Future<String?> readUserJson() => _storage.read(key: _userKey);

  Future<void> clear() async {
    _accessTokenCache = null;
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userKey);
  }
}
