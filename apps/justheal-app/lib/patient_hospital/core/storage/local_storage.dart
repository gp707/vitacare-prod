import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for session persistence.
/// CLAUDE.md: no offline write queueing — this only persists auth tokens.
class LocalStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _readMessageIdsKey = 'read_message_ids';

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

  /// On-device only — which NurseNow Individual message template ids the
  /// user has already seen (see MessagesBellButton). No backend/account
  /// sync; local-device tracking was a deliberate choice to keep this
  /// feature's "no persistence layer, fetched fresh" architecture intact.
  Set<String> get readMessageIds => (_prefs.getStringList(_readMessageIdsKey) ?? const []).toSet();

  Future<void> markMessagesRead(Iterable<String> ids) async {
    final updated = {...readMessageIds, ...ids};
    await _prefs.setStringList(_readMessageIdsKey, updated.toList());
  }
}
