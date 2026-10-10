package `in`.vitacasahealth.nativejustheal

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Hits the real production backend — same base URL the Flutter app's own
 * ApiClient (lib/caregiver/core/network/api_client.dart) uses in release
 * mode. No local-dev URL/10.0.2.2 mapping wired up for this POC; production
 * is reachable from any device/emulator with real internet, which is enough
 * to prove the network layer actually round-trips real requests.
 */
private const val BASE_URL = "https://api.vitacasahealth.in/v1"

sealed class ApiResult<out T> {
    data class Success<T>(val data: T) : ApiResult<T>()
    data class Failure(val message: String) : ApiResult<Nothing>()
}

data class AuthTokens(val accessToken: String, val refreshToken: String)

object ApiClient {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .build()

    private val jsonMediaType = "application/json".toMediaType()

    /** Every caregiver-facing endpoint past login/register needs the
     * bearer token — threaded through explicitly as a parameter rather
     * than a global/singleton Context reference, so ApiClient itself
     * stays free of an Android Context dependency (easier to reason
     * about, closer to how the real app's own Dio interceptor is
     * configured once at startup rather than read ad hoc per call). */
    private suspend fun request(
        method: String,
        path: String,
        token: String? = null,
        body: JSONObject? = null,
    ): ApiResult<Any> = withContext(Dispatchers.IO) {
        try {
            val builder = Request.Builder().url("$BASE_URL$path")
            token?.let { builder.addHeader("Authorization", "Bearer $it") }
            val requestBody = body?.toString()?.toRequestBody(jsonMediaType)
            when (method) {
                "GET" -> builder.get()
                "POST" -> builder.post(requestBody ?: JSONObject().toString().toRequestBody(jsonMediaType))
                "PATCH" -> builder.patch(requestBody ?: JSONObject().toString().toRequestBody(jsonMediaType))
                "PUT" -> builder.put(requestBody ?: JSONObject().toString().toRequestBody(jsonMediaType))
                "DELETE" -> builder.delete(requestBody)
            }
            client.newCall(builder.build()).execute().use { response ->
                val raw = response.body?.string().orEmpty()
                // A 204/empty-body success (nothing this app hits yet, but
                // DELETE can legitimately have no body) still counts as
                // success without trying to parse an empty string as JSON.
                if (response.isSuccessful && raw.isBlank()) return@use ApiResult.Success(JSONObject())
                val json = if (raw.isNotBlank()) JSONObject(raw) else JSONObject()
                if (response.isSuccessful && json.optBoolean("success", false)) {
                    // 'data' can legitimately be a bare JSONArray (every
                    // list endpoint) as well as a JSONObject — callers cast
                    // to whichever shape they expect.
                    ApiResult.Success(if (json.has("data")) json.get("data") else JSONObject())
                } else {
                    val message = json.optJSONObject("error")?.optString("message")
                        ?: "Something went wrong (HTTP ${response.code})"
                    ApiResult.Failure(message)
                }
            }
        } catch (e: Exception) {
            ApiResult.Failure(e.message ?: "Network error — check your connection")
        }
    }

    private suspend fun post(path: String, body: JSONObject): ApiResult<JSONObject> =
        when (val result = request("POST", path, body = body)) {
            is ApiResult.Success -> ApiResult.Success(result.data as JSONObject)
            is ApiResult.Failure -> result
        }

    private suspend fun getAuthed(path: String, token: String): ApiResult<Any> = request("GET", path, token = token)

    private suspend fun postAuthed(path: String, token: String, body: JSONObject = JSONObject()): ApiResult<JSONObject> =
        when (val result = request("POST", path, token = token, body = body)) {
            is ApiResult.Success -> ApiResult.Success(result.data as JSONObject)
            is ApiResult.Failure -> result
        }

    private suspend fun putAuthed(path: String, token: String, body: JSONObject): ApiResult<JSONObject> =
        when (val result = request("PUT", path, token = token, body = body)) {
            is ApiResult.Success -> ApiResult.Success(result.data as JSONObject)
            is ApiResult.Failure -> result
        }

    private suspend fun deleteAuthed(path: String, token: String, body: JSONObject): ApiResult<JSONObject> =
        when (val result = request("DELETE", path, token = token, body = body)) {
            is ApiResult.Success -> ApiResult.Success(result.data as JSONObject)
            is ApiResult.Failure -> result
        }

    /** POST /auth/login/code — LoginCodeDto { phone, code, app }. Caregiver
     * app always sends app: 'nursejobs' (see LoginApp enum,
     * apps/api/src/auth/dto/login-code.dto.ts). */
    suspend fun loginCode(phone: String, code: String): ApiResult<AuthTokens> {
        val body = JSONObject().apply {
            put("phone", phone)
            put("code", code)
            put("app", "nursejobs")
        }
        return when (val result = post("/auth/login/code", body)) {
            is ApiResult.Success -> ApiResult.Success(
                AuthTokens(
                    accessToken = result.data.getString("access_token"),
                    refreshToken = result.data.getString("refresh_token"),
                ),
            )
            is ApiResult.Failure -> result
        }
    }

    /** POST /auth/register — RegisterDto (apps/api/src/auth/dto/register.dto.ts).
     * Document upload (selfie/Aadhaar, their own multipart endpoints in the
     * real app) is out of scope for this POC — see MainActivity's Register
     * screen for the explicit placeholder. */
    suspend fun register(
        phone: String,
        fullName: String,
        gender: String,
        age: Int,
        languages: List<String>,
        religion: String,
        highestQualification: String,
        code: String,
    ): ApiResult<AuthTokens> {
        val body = JSONObject().apply {
            put("phone", phone)
            put("full_name", fullName)
            put("gender", gender)
            put("age", age)
            put("languages", JSONArray(languages))
            put("religion", religion)
            put("highest_qualification", highestQualification)
            put("terms_accepted", true)
            put("code", code)
        }
        return when (val result = post("/auth/register", body)) {
            is ApiResult.Success -> ApiResult.Success(
                AuthTokens(
                    accessToken = result.data.getString("access_token"),
                    refreshToken = result.data.getString("refresh_token"),
                ),
            )
            is ApiResult.Failure -> result
        }
    }

    // ---- Phase 2: full caregiver flow. Routes confirmed directly against
    // apps/api/src/{jobs/caregiver-jobs.controller.ts,
    // organisation/caregiver-organisation-requirements.controller.ts,
    // caregiver/caregiver.controller.ts}, not guessed from CLAUDE.md prose.

    suspend fun getJobs(token: String): ApiResult<List<JobModel>> =
        when (val result = getAuthed("/caregiver/jobs", token)) {
            is ApiResult.Success -> ApiResult.Success(
                (result.data as JSONArray).let { arr -> (0 until arr.length()).map { JobModel.fromJson(arr.getJSONObject(it)) } },
            )
            is ApiResult.Failure -> result
        }

    suspend fun getAssignedJobs(token: String): ApiResult<List<JobModel>> =
        when (val result = getAuthed("/caregiver/jobs/assigned", token)) {
            is ApiResult.Success -> ApiResult.Success(
                (result.data as JSONArray).let { arr -> (0 until arr.length()).map { JobModel.fromJson(arr.getJSONObject(it)) } },
            )
            is ApiResult.Failure -> result
        }

    suspend fun getOrganisationRequirements(token: String): ApiResult<List<OrganisationRequirementModel>> =
        when (val result = getAuthed("/caregiver/organisation-requirements", token)) {
            is ApiResult.Success -> ApiResult.Success(
                (result.data as JSONArray).let { arr ->
                    (0 until arr.length()).map { OrganisationRequirementModel.fromJson(arr.getJSONObject(it)) }
                },
            )
            is ApiResult.Failure -> result
        }

    suspend fun getAssignedOrganisationRequirements(token: String): ApiResult<List<OrganisationRequirementModel>> =
        when (val result = getAuthed("/caregiver/organisation-requirements/assigned", token)) {
            is ApiResult.Success -> ApiResult.Success(
                (result.data as JSONArray).let { arr ->
                    (0 until arr.length()).map { OrganisationRequirementModel.fromJson(arr.getJSONObject(it)) }
                },
            )
            is ApiResult.Failure -> result
        }

    /** [status] is JobApplicationStatus.APPLIED or .REJECTED — see
     * ApplyJobDto, caregiver-only, 'accepted' is admin-only. */
    suspend fun applyToJob(token: String, jobId: String, status: String): ApiResult<JSONObject> =
        postAuthed("/caregiver/jobs/$jobId/apply", token, JSONObject().put("status", status))

    suspend fun applyToRequirement(token: String, requirementId: String, status: String): ApiResult<JSONObject> =
        postAuthed(
            "/caregiver/organisation-requirements/$requirementId/apply",
            token,
            JSONObject().put("status", status),
        )

    /** CompleteJobDto's close_reason is optional, defaults server-side —
     * not collected in this phase's UI, so always sent empty. */
    suspend fun completeJob(token: String, jobId: String): ApiResult<JSONObject> =
        postAuthed("/caregiver/jobs/$jobId/complete", token)

    suspend fun completeRequirement(token: String, requirementId: String): ApiResult<JSONObject> =
        postAuthed("/caregiver/organisation-requirements/$requirementId/complete", token)

    suspend fun getProfile(token: String): ApiResult<CaregiverProfileModel> =
        when (val result = getAuthed("/caregiver/profile", token)) {
            is ApiResult.Success -> ApiResult.Success(CaregiverProfileModel.fromJson(result.data as JSONObject))
            is ApiResult.Failure -> result
        }

    /** DeleteAccountDto { code } — re-entering the login PIN, the one
     * re-auth step in this product's self-service flows (irreversible). */
    suspend fun deleteAccount(token: String, code: String): ApiResult<JSONObject> =
        deleteAuthed("/caregiver/account", token, JSONObject().put("code", code))

    suspend fun updateFcmToken(token: String, fcmToken: String): ApiResult<JSONObject> =
        putAuthed("/caregiver/fcm-token", token, JSONObject().put("token", fcmToken))

    /** Public, no auth — GET /rate-card always returns both frequency rows. */
    suspend fun getRateCard(): ApiResult<List<RateCardModel>> =
        when (val result = request("GET", "/rate-card")) {
            is ApiResult.Success -> ApiResult.Success(
                (result.data as JSONArray).let { arr -> (0 until arr.length()).map { RateCardModel.fromJson(arr.getJSONObject(it)) } },
            )
            is ApiResult.Failure -> result
        }

    suspend fun getScopeOfWork(): ApiResult<ScopeOfWorkModel> =
        when (val result = request("GET", "/scope-of-work")) {
            is ApiResult.Success -> ApiResult.Success(ScopeOfWorkModel.fromJson(result.data as JSONObject))
            is ApiResult.Failure -> result
        }

    suspend fun getDutyRequirements(): ApiResult<DutyRequirementsModel> =
        when (val result = request("GET", "/duty-requirements")) {
            is ApiResult.Success -> ApiResult.Success(DutyRequirementsModel.fromJson(result.data as JSONObject))
            is ApiResult.Failure -> result
        }

    /** ForgotPinDto { phone } — public, no auth, reachable before login.
     * Creates a support ticket; backend returns a plain message string. */
    suspend fun forgotPin(phone: String): ApiResult<String> =
        when (val result = post("/auth/forgot-pin", JSONObject().put("phone", phone))) {
            is ApiResult.Success -> ApiResult.Success(result.data.optString("message", "Request submitted."))
            is ApiResult.Failure -> result
        }

    /** POST /caregiver/profile/selfie — multipart field name confirmed
     * against FileInterceptor('file') in caregiver.controller.ts. */
    suspend fun uploadSelfie(token: String, file: File): ApiResult<JSONObject> =
        uploadMultipart("/caregiver/profile/selfie", token, file, extraField = null)

    /** POST /caregiver/profile/documents — multipart field 'file' plus a
     * document_type form field (UploadDocumentDto). [documentType] is
     * DocumentType.AADHAAR/.QUALIFICATION/.OTHER. */
    suspend fun uploadDocument(token: String, file: File, documentType: String): ApiResult<JSONObject> =
        uploadMultipart("/caregiver/profile/documents", token, file, extraField = "document_type" to documentType)

    private suspend fun uploadMultipart(
        path: String,
        token: String,
        file: File,
        extraField: Pair<String, String>?,
    ): ApiResult<JSONObject> = withContext(Dispatchers.IO) {
        try {
            val bodyBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)
                .addFormDataPart("file", file.name, file.asRequestBody("image/jpeg".toMediaType()))
            extraField?.let { (key, value) -> bodyBuilder.addFormDataPart(key, value) }
            val request = Request.Builder()
                .url("$BASE_URL$path")
                .addHeader("Authorization", "Bearer $token")
                .post(bodyBuilder.build())
                .build()
            client.newCall(request).execute().use { response ->
                val raw = response.body?.string().orEmpty()
                val json = if (raw.isNotBlank()) JSONObject(raw) else JSONObject()
                if (response.isSuccessful && json.optBoolean("success", false)) {
                    ApiResult.Success(json.optJSONObject("data") ?: JSONObject())
                } else {
                    val message = json.optJSONObject("error")?.optString("message")
                        ?: "Upload failed (HTTP ${response.code})"
                    ApiResult.Failure(message)
                }
            }
        } catch (e: Exception) {
            ApiResult.Failure(e.message ?: "Upload failed — check your connection")
        }
    }
}
