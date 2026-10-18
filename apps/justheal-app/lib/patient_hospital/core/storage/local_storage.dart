import 'package:shared_preferences/shared_preferences.dart';

/// Thin wrapper around SharedPreferences for session persistence.
/// CLAUDE.md: no offline write queueing — this only persists auth tokens.
class LocalStorage {
  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _readMessageIdsKey = 'read_message_ids';
  // Deliberately the same unprefixed key as the caregiver tree's own
  // LocalStorage — both read/write the same underlying SharedPreferences
  // file (one installed binary, see CLAUDE.md's JustHeal merge notes), so
  // a senior's chosen text size stays consistent whether they're on the
  // patient/hospital side or the caregiver side, rather than being a
  // separate per-flow setting that resets when they cross between them.
  static const _textScaleKey = 'text_scale';

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

  /// Accessibility text/UI scale — 1.0 (Normal) if never set. See
  /// core/text_scale/text_scale_provider.dart.
  double get textScale => _prefs.getDouble(_textScaleKey) ?? 1.0;

  Future<void> setTextScale(double scale) => _prefs.setDouble(_textScaleKey, scale);
}
