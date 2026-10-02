import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for session persistence.
/// CLAUDE.md: no offline write queueing — this only persists auth tokens.
///
/// Keys are prefixed `caregiver_` because this LocalStorage now shares one
/// SharedPreferences instance with the host JustHeal app's own LocalStorage
/// (same app/binary, same key-value namespace, post-merge) — without the
/// prefix, a caregiver logging in and a patient/organisation logging in
/// would silently overwrite each other's tokens under the same bare key
/// names (both copies of this class originally used identical unprefixed
/// keys before the merge).
class LocalStorage {
  static const _accessTokenKey = 'caregiver_access_token';
  static const _refreshTokenKey = 'caregiver_refresh_token';
  static const _readMessageIdsKey = 'caregiver_read_message_ids';

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

  /// On-device only — which NurseJobs message template ids the user has
  /// already seen (see MessagesBellButton). No backend/account sync;
  /// local-device tracking was a deliberate choice to keep this feature's
  /// "no persistence layer, fetched fresh" architecture intact.
  Set<String> get readMessageIds => (_prefs.getStringList(_readMessageIdsKey) ?? const []).toSet();

  Future<void> markMessagesRead(Iterable<String> ids) async {
    final updated = {...readMessageIds, ...ids};
    await _prefs.setStringList(_readMessageIdsKey, updated.toList());
  }
}
