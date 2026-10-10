package `in`.vitacasahealth.nativejustheal

import org.json.JSONObject

/**
 * Plain data classes + fromJson parsing, mirroring the real app's shared
 * Dart models field-for-field — ground truth taken directly from
 * packages/vitacare_shared/lib/models/{job_model,care_receiver_model,
 * organisation_requirement_model}.dart, not re-derived from CLAUDE.md
 * prose. No codegen (matching the product's own "no json_serializable in
 * shared packages" rule, applied here by the same logic even though this
 * isn't a shared package).
 */

private fun JSONObject.optStringList(key: String): List<String> {
    val arr = optJSONArray(key) ?: return emptyList()
    return (0 until arr.length()).map { arr.getString(it) }
}

/** org.json's own optString(key, fallback) treats [fallback] as a Java
 * non-null String, so passing Kotlin's `null` literal there compiles but
 * produces a platform-type mismatch warning at every call site. isNull()
 * correctly covers both "key absent" and "key present with JSON null" per
 * org.json's own docs, so this avoids the two-arg overload entirely. */
private fun JSONObject.optStringOrNull(key: String): String? = if (isNull(key)) null else getString(key)

data class MyApplicationModel(
    val status: String,
    val appliedAt: String?,
    val acceptedAt: String?,
    val rejectedAt: String?,
    val completedAt: String?,
    val reappliedAt: String?,
    val decidedByAdmin: Boolean,
    val declineReason: String?,
    val closeReason: String?,
) {
    companion object {
        fun fromJson(json: JSONObject) = MyApplicationModel(
            status = json.getString("status"),
            appliedAt = json.optStringOrNull("applied_at"),
            acceptedAt = json.optStringOrNull("accepted_at"),
            rejectedAt = json.optStringOrNull("rejected_at"),
            completedAt = json.optStringOrNull("completed_at"),
            reappliedAt = json.optStringOrNull("reapplied_at"),
            decidedByAdmin = json.optBoolean("decided_by_admin", false),
            declineReason = json.optStringOrNull("decline_reason"),
            closeReason = json.optStringOrNull("close_reason"),
        )
    }

    /** Mirrors _appliedAtOf in jobs_screen.dart — "when was this
     * still-applied application last actioned", used to find the single
     * most-recently-applied listing across a merged jobs+requirements list. */
    fun appliedAtOrNull(): String? = if (status == JobApplicationStatus.APPLIED) (reappliedAt ?: appliedAt) else null
}

data class CareReceiverModel(
    val id: String,
    val age: Int,
    val gender: String,
    val weightKg: Int,
    val feedingType: String,
    val hasMedicalCondition: Boolean,
    val medicalConditions: List<String>,
    val medicalConditionOther: String?,
    val toiletAssistance: List<String>,
    val toiletAssistanceOther: String?,
    val requiresVitalMonitoring: Boolean,
    val vitalMonitoringTypes: List<String>,
) {
    companion object {
        fun fromJson(json: JSONObject) = CareReceiverModel(
            id = json.getString("id"),
            age = json.getInt("age"),
            gender = json.getString("gender"),
            weightKg = json.getInt("weight_kg"),
            feedingType = json.getString("feeding_type"),
            hasMedicalCondition = json.optBoolean("has_medical_condition", false),
            medicalConditions = json.optStringList("medical_conditions"),
            medicalConditionOther = json.optStringOrNull("medical_condition_other"),
            toiletAssistance = json.optStringList("toilet_assistance"),
            toiletAssistanceOther = json.optStringOrNull("toilet_assistance_other"),
            requiresVitalMonitoring = json.optBoolean("requires_vital_monitoring", false),
            vitalMonitoringTypes = json.optStringList("vital_monitoring_types"),
        )
    }
}

data class JobPosterModel(val fullName: String, val phone: String) {
    companion object {
        fun fromJson(json: JSONObject) = JobPosterModel(json.getString("full_name"), json.getString("phone"))
    }
}

data class JobModel(
    val id: String,
    val adminJobNumber: Int?,
    val patientJobNumber: Int?,
    val city: String,
    val area: String?,
    val description: String?,
    val dutyType: String,
    val frequencyOfCare: String?,
    val startDate: String?,
    val languages: List<String>,
    val salaryAmount: String?,
    val preferredGender: String?,
    val preferredReligion: String?,
    val careDuration: String?,
    val status: String,
    val postedAt: String,
    val myApplication: MyApplicationModel?,
    val careReceiver: CareReceiverModel?,
    val jobPoster: JobPosterModel?,
    val rejectionReason: String?,
    val applicantCount: Int?,
) {
    companion object {
        fun fromJson(json: JSONObject) = JobModel(
            id = json.getString("id"),
            adminJobNumber = if (json.isNull("admin_job_number")) null else json.optInt("admin_job_number"),
            patientJobNumber = if (json.isNull("patient_job_number")) null else json.optInt("patient_job_number"),
            city = json.getString("city"),
            area = json.optStringOrNull("area"),
            description = json.optStringOrNull("description"),
            dutyType = json.getString("duty_type"),
            frequencyOfCare = json.optStringOrNull("frequency_of_care"),
            startDate = json.optStringOrNull("start_date"),
            languages = json.optStringList("languages"),
            salaryAmount = json.optStringOrNull("salary_amount"),
            preferredGender = json.optStringOrNull("preferred_gender"),
            preferredReligion = json.optStringOrNull("preferred_religion"),
            careDuration = json.optStringOrNull("care_duration"),
            status = json.getString("status"),
            postedAt = json.getString("posted_at"),
            myApplication = json.optJSONObject("my_application")?.let { MyApplicationModel.fromJson(it) },
            careReceiver = json.optJSONObject("care_receiver")?.let { CareReceiverModel.fromJson(it) },
            jobPoster = json.optJSONObject("job_poster")?.let { JobPosterModel.fromJson(it) },
            rejectionReason = json.optStringOrNull("rejection_reason"),
            applicantCount = if (json.isNull("applicant_count")) null else json.optInt("applicant_count"),
        )
    }
}

/** "ADMIN-JOB-<n>" or "PAT-JOB-<n>" — mirrors jobDisplayId() in job_model.dart. */
fun jobDisplayId(job: JobModel): String = when {
    job.adminJobNumber != null -> "ADMIN-JOB-${job.adminJobNumber}"
    job.patientJobNumber != null -> "PAT-JOB-${job.patientJobNumber}"
    else -> error("Job ${job.id} has neither adminJobNumber nor patientJobNumber set")
}

data class OrganisationRequirementModel(
    val id: String,
    val requirementNumber: Int,
    val typeOfNurse: String,
    val typeOfNurseOther: String?,
    val accommodationProvided: Boolean,
    val foodProvided: Boolean,
    val specialSkills: String?,
    val numberOfVacancies: Int,
    val preferredGender: String?,
    val durationType: String?,
    val status: String,
    val postedAt: String,
    val organisationName: String?,
    val organisationType: String?,
    val city: String?,
    val area: String?,
    val organisationPhone: String?,
    val myApplication: MyApplicationModel?,
    val applicantCount: Int?,
) {
    companion object {
        fun fromJson(json: JSONObject) = OrganisationRequirementModel(
            id = json.getString("id"),
            requirementNumber = json.getInt("requirement_number"),
            typeOfNurse = json.getString("type_of_nurse"),
            typeOfNurseOther = json.optStringOrNull("type_of_nurse_other"),
            accommodationProvided = json.getBoolean("accommodation_provided"),
            foodProvided = json.getBoolean("food_provided"),
            specialSkills = json.optStringOrNull("special_skills"),
            numberOfVacancies = json.getInt("number_of_vacancies"),
            preferredGender = json.optStringOrNull("preferred_gender"),
            durationType = json.optStringOrNull("duration_type"),
            status = json.getString("status"),
            postedAt = json.getString("posted_at"),
            organisationName = json.optStringOrNull("organisation_name"),
            organisationType = json.optStringOrNull("organisation_type"),
            city = json.optStringOrNull("city"),
            area = json.optStringOrNull("area"),
            organisationPhone = json.optStringOrNull("organisation_phone"),
            myApplication = json.optJSONObject("my_application")?.let { MyApplicationModel.fromJson(it) },
            applicantCount = if (json.isNull("applicant_count")) null else json.optInt("applicant_count"),
        )
    }
}

/** "ORG-JOB-<n>" — mirrors organisationJobDisplayId() in organisation_requirement_model.dart. */
fun organisationJobDisplayId(requirement: OrganisationRequirementModel) = "ORG-JOB-${requirement.requirementNumber}"

/**
 * Caregiver's own profile (GET /caregiver/profile) — ground truth is
 * packages/vitacare_shared/lib/models/caregiver_profile_model.dart's own
 * fromJson, NOT a guess — note userId/profileId are two distinct fields
 * (users.id vs caregiver_profiles.id), there is no bare "id". Only the
 * fields this phase's screens actually use are included here; document
 * URLs/preferredCities/email/rejectionMessage are deferred (see
 * ProfileScreen's own doc comment for the exact cut list) — add them here
 * first if a later screen needs them, rather than guessing their shape.
 */
data class CaregiverProfileModel(
    val userId: String,
    val profileId: String,
    val fullName: String,
    val phone: String,
    val gender: String,
    val age: Int,
    val languages: List<String>,
    val religion: String?,
    val highestQualification: String?,
    val verificationStatus: String,
    val caregiverNumber: Int?,
) {
    companion object {
        fun fromJson(json: JSONObject) = CaregiverProfileModel(
            userId = json.getString("user_id"),
            profileId = json.getString("profile_id"),
            fullName = json.getString("full_name"),
            phone = json.getString("phone"),
            gender = json.getString("gender"),
            age = json.getInt("age"),
            languages = json.optStringList("languages"),
            religion = json.optStringOrNull("religion"),
            highestQualification = json.optStringOrNull("highest_qualification"),
            verificationStatus = json.getString("verification_status"),
            caregiverNumber = if (json.isNull("caregiver_number")) null else json.optInt("caregiver_number"),
        )
    }
}

/** "NUR-<n>" — mirrors caregiverDisplayId() in display_id.dart. */
fun caregiverDisplayId(profile: CaregiverProfileModel): String? =
    profile.caregiverNumber?.let { "NUR-$it" }

/** GET /rate-card — always returns both frequency rows. */
data class RateCardModel(
    val frequencyOfCare: String,
    val title: String,
    val columnLabels: List<String>,
    val rowLabels: List<String>,
    val cells: List<List<String>>,
) {
    companion object {
        fun fromJson(json: JSONObject): RateCardModel {
            val cellsArr = json.getJSONArray("cells")
            val cells = (0 until cellsArr.length()).map { r ->
                val row = cellsArr.getJSONArray(r)
                (0 until row.length()).map { c -> row.getString(c) }
            }
            return RateCardModel(
                frequencyOfCare = json.getString("frequency_of_care"),
                title = json.getString("title"),
                columnLabels = json.optStringList("column_labels"),
                rowLabels = json.optStringList("row_labels"),
                cells = cells,
            )
        }
    }
}

/** GET /scope-of-work — one cumulative bullet list per tier. */
data class ScopeOfWorkModel(
    val companionCare: List<String>,
    val bedsideCare: List<String>,
    val criticalCare: List<String>,
) {
    companion object {
        fun fromJson(json: JSONObject) = ScopeOfWorkModel(
            companionCare = json.optStringList("companion_care"),
            bedsideCare = json.optStringList("bedside_care"),
            criticalCare = json.optStringList("critical_care"),
        )
    }

    /** Cumulative, matching ScopeOfWorkModel.bulletsFor in the Dart model —
     * Bedside includes Companion's bullets, Critical includes both. */
    fun bulletsFor(tier: String): List<String> = when (tier) {
        CareTier.COMPANION_CARE -> companionCare
        CareTier.BEDSIDE_CARE -> companionCare + bedsideCare
        CareTier.CRITICAL_CARE -> companionCare + bedsideCare + criticalCare
        else -> emptyList()
    }
}

/** GET /duty-requirements — one independent (non-cumulative) list per shift. */
data class DutyRequirementsModel(
    val liveIn: List<String>,
    val dayDuty: List<String>,
    val nightDuty: List<String>,
) {
    companion object {
        fun fromJson(json: JSONObject) = DutyRequirementsModel(
            liveIn = json.optStringList("live_in"),
            dayDuty = json.optStringList("day_duty"),
            nightDuty = json.optStringList("night_duty"),
        )
    }

    fun bulletsFor(dutyType: String): List<String> = when (dutyType) {
        DutyType.LIVE_IN -> liveIn
        DutyType.DAY_DUTY -> dayDuty
        DutyType.NIGHT_DUTY -> nightDuty
        else -> emptyList()
    }
}
