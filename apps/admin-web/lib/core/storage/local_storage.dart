import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences (backed by browser localStorage on
/// web) for persisting the admin's session across page reloads.
class LocalStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  final SharedPreferences _prefs;

  LocalStorage(this._prefs);

  static Future<LocalStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalStorage(prefs);
  }

  String? get accessToken => _prefs.getString(_accessTokenKey);
  String? get refreshToken => _prefs.getString(_refreshTokenKey);

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _prefs.setString(_accessTokenKey, accessToken);
    await _prefs.setString(_refreshTokenKey, refreshToken);
  }

  Future<void> clearTokens() async {
    await _prefs.remove(_accessTokenKey);
    await _prefs.remove(_refreshTokenKey);
  }
}
