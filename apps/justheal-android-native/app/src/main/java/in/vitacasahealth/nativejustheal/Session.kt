package `in`.vitacasahealth.nativejustheal

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Persists the caregiver's JWT across app restarts — the Flutter app's own
 * caregiver-app token never expires (no `exp` claim, see CLAUDE.md's Auth
 * section), so "stay logged in" is the only behavior to match. Uses
 * EncryptedSharedPreferences rather than plain SharedPreferences since this
 * holds a live bearer token — the native-platform equivalent of what
 * flutter_secure_storage gives the Flutter app.
 */
object Session {
    private const val PREFS_NAME = "session"
    private const val KEY_ACCESS_TOKEN = "access_token"
    private const val KEY_PROFILE_ID = "caregiver_profile_id"

    private fun prefs(context: Context) = EncryptedSharedPreferences.create(
        context,
        PREFS_NAME,
        MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
    )

    fun save(context: Context, accessToken: String) {
        prefs(context).edit().putString(KEY_ACCESS_TOKEN, accessToken).apply()
    }

    fun accessToken(context: Context): String? = prefs(context).getString(KEY_ACCESS_TOKEN, null)

    fun isLoggedIn(context: Context): Boolean = accessToken(context) != null

    /** Caregiver's own profile id (caregiver_profiles.id) — cached locally
     * after the first GET /caregiver/profile so screens that need it (none
     * yet in this phase, kept for the next one) don't have to refetch. */
    fun saveProfileId(context: Context, id: String) {
        prefs(context).edit().putString(KEY_PROFILE_ID, id).apply()
    }

    fun profileId(context: Context): String? = prefs(context).getString(KEY_PROFILE_ID, null)

    fun logout(context: Context) {
        prefs(context).edit().clear().apply()
    }
}
