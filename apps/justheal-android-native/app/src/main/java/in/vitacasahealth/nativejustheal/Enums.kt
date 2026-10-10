package `in`.vitacasahealth.nativejustheal

/**
 * Mirrors packages/shared-constants/src/enums.ts and
 * packages/vitacare_shared/lib/constants/enums.dart exactly — values and
 * display labels copied by hand for this POC rather than codegen'd, since
 * there's no cross-language shared-constants story for a native app (the
 * real product's own "Sync Rule" — keep TS and Dart in sync by hand on every
 * change — would need a *third* hand-kept copy here, which is exactly the
 * recurring cost a native rewrite was flagged as introducing).
 */
object Gender {
    const val MALE = "male"
    const val FEMALE = "female"
    const val OTHER = "other"
    val all = listOf(MALE, FEMALE, OTHER)
}

object Language {
    const val HINDI = "hindi"
    const val ENGLISH = "english"
    const val KANNADA = "kannada"
    const val TAMIL = "tamil"
    const val TELUGU = "telugu"
    const val MALAYALAM = "malayalam"
    const val BENGALI = "bengali"
    const val GUJARATI = "gujarati"
    const val MARATHI = "marathi"
    val all = listOf(HINDI, ENGLISH, KANNADA, TAMIL, TELUGU, MALAYALAM, BENGALI, GUJARATI, MARATHI)
    val displayNames = mapOf(
        HINDI to "Hindi", ENGLISH to "English", KANNADA to "Kannada", TAMIL to "Tamil",
        TELUGU to "Telugu", MALAYALAM to "Malayalam", BENGALI to "Bengali",
        GUJARATI to "Gujarati", MARATHI to "Marathi",
    )
}

object Religion {
    const val HINDU = "hindu"
    const val MUSLIM = "muslim"
    const val CHRISTIAN = "christian"
    const val OTHERS = "others"
    val all = listOf(HINDU, MUSLIM, CHRISTIAN, OTHERS)
    val displayNames = mapOf(
        HINDU to "Hindu", MUSLIM to "Muslim", CHRISTIAN to "Christian", OTHERS to "Others",
    )
}

object Qualification {
    const val RN_ABOVE_2_YEARS = "rn_above_2_years"
    const val RN_BELOW_2_YEARS = "rn_below_2_years"
    const val REGISTERED_RECENTLY = "registered_recently"
    const val BSC_GNM_UNREGISTERED = "bsc_gnm_unregistered"
    const val ANM_STUDENT_BACKLOG = "anm_student_backlog"
    const val GDA_NON_NURSING = "gda_non_nursing"
    val all = listOf(
        RN_ABOVE_2_YEARS, RN_BELOW_2_YEARS, REGISTERED_RECENTLY,
        BSC_GNM_UNREGISTERED, ANM_STUDENT_BACKLOG, GDA_NON_NURSING,
    )
    val displayNames = mapOf(
        RN_ABOVE_2_YEARS to "Registered Nurse above 2 years of experience",
        RN_BELOW_2_YEARS to "Registered Nurse below 2 years experience",
        REGISTERED_RECENTLY to "Registered Recently",
        BSC_GNM_UNREGISTERED to "BSC / GNM Completed - Unregistered",
        ANM_STUDENT_BACKLOG to "ANM/Nursing Student/ Backlog",
        GDA_NON_NURSING to "GDA / Non Nursing",
    )
}

object VerificationStatus {
    const val PENDING_CALL = "pending_call"
    const val AVAILABLE = "available"
    const val UNAVAILABLE = "unavailable"
    const val ASSIGNED = "assigned"
    const val REJECTED = "rejected"
}

object JobApplicationStatus {
    const val APPLIED = "applied"
    const val REJECTED = "rejected"
    const val ACCEPTED = "accepted"
    const val COMPLETED = "completed"
}

object DutyType {
    const val LIVE_IN = "live_in"
    const val DAY_DUTY = "day_duty"
    const val NIGHT_DUTY = "night_duty"
    val displayNames = mapOf(
        LIVE_IN to "24Hrs - Live In",
        DAY_DUTY to "12Hrs Day Shift (8am to 8pm)",
        NIGHT_DUTY to "12Hrs Night Shift (8pm to 8am)",
    )
}

object FrequencyOfCare {
    const val DAILY = "daily"
    const val MONTHLY = "monthly"
}

object CareDuration {
    const val FEW_DAYS = "few_days"
    const val FEW_WEEKS = "few_weeks"
    const val FEW_MONTHS = "few_months"
    const val LONG_TERM = "long_term"
    val displayNames = mapOf(
        FEW_DAYS to "Need for few Days", FEW_WEEKS to "Need for Few Weeks",
        FEW_MONTHS to "Need for Minimum a Month", LONG_TERM to "Need for Long Term",
    )
}

object City {
    val all = listOf("bangalore", "mumbai", "hyderabad", "chennai", "pune", "delhi", "gurgaon")
    val displayNames = mapOf(
        "bangalore" to "Bangalore", "mumbai" to "Mumbai", "hyderabad" to "Hyderabad",
        "chennai" to "Chennai", "pune" to "Pune", "delhi" to "Delhi", "gurgaon" to "Gurgaon",
    )
}

object FeedingType {
    const val ORAL_FEEDING = "oral_feeding"
    const val TUBE_FEEDING = "tube_feeding"
    const val OTHERS = "others"
    val displayNames = mapOf(
        ORAL_FEEDING to "Oral feeding", TUBE_FEEDING to "Tube feeding", OTHERS to "Others (Cannula etc.)",
    )
}

object ToiletAssistance {
    const val INDEPENDENT = "independent"
    const val DIAPERS_BEDSIDE_SUPPORT = "diapers_bedside_support"
    const val USES_CATHETER = "uses_catheter"
    const val OTHERS = "others"
    val displayNames = mapOf(
        INDEPENDENT to "Independent/minimal support",
        DIAPERS_BEDSIDE_SUPPORT to "Diapers/bedside support",
        USES_CATHETER to "Catheter support",
        OTHERS to "Others",
    )
}

object MedicalCondition {
    val displayNames = mapOf(
        "cancer" to "Cancer", "stroke" to "Stroke", "brain_injury" to "Brain Injury",
        "dementia_alzheimers" to "Dementia/Alzheimer's", "parkinsons" to "Parkinson's",
        "heart_condition" to "Heart Condition", "kidney_disease_dialysis" to "Kidney Disease/Dialysis",
        "diabetes" to "Diabetes", "colostomy" to "Colostomy", "paralysis" to "Paralysis", "tb" to "TB",
        "bp" to "BP", "oxygen_support" to "Oxygen support",
        "insulin_administration_support" to "Insulin administration support",
        "injection_support" to "Injection support", "cannula_care" to "Cannula care",
        "catheter_care" to "Catheter care", "nebulisation_support" to "Nebulisation support",
        "other" to "Other",
    )
}

object VitalMonitoringType {
    val displayNames = mapOf(
        "blood_pressure" to "Blood Pressure", "blood_sugar" to "Blood Sugar",
        "oxygen_spo2" to "Oxygen (SpO2)", "temperature" to "Temperature",
        "pulse" to "Pulse", "other" to "Other",
    )
}

object CareTier {
    const val COMPANION_CARE = "companion_care"
    const val BEDSIDE_CARE = "bedside_care"
    const val CRITICAL_CARE = "critical_care"
    val displayNames = mapOf(
        COMPANION_CARE to "Companion Care", BEDSIDE_CARE to "Bedside Care", CRITICAL_CARE to "Critical Care",
    )

    /** Mirrors deriveCareTier() in care_tier.dart exactly — highest-tier-first. */
    fun derive(careReceiver: CareReceiverModel): String {
        val isCritical = careReceiver.toiletAssistance.contains(ToiletAssistance.USES_CATHETER) ||
            careReceiver.toiletAssistance.contains(ToiletAssistance.OTHERS) ||
            careReceiver.feedingType == FeedingType.TUBE_FEEDING ||
            careReceiver.feedingType == FeedingType.OTHERS
        if (isCritical) return CRITICAL_CARE
        if (careReceiver.toiletAssistance.contains(ToiletAssistance.DIAPERS_BEDSIDE_SUPPORT)) return BEDSIDE_CARE
        return COMPANION_CARE
    }
}

object OrganisationType {
    val displayNames = mapOf(
        "hospital" to "Hospital", "rehab" to "Rehab", "clinic" to "Clinic", "agency" to "Agency",
    )
}

object TypeOfNurse {
    val displayNames = mapOf(
        "registered_nurse" to "Registered Nurse", "nursing_completed" to "Nursing Completed Nurses",
        "nursing_student" to "Nursing Students", "auxiliary_nurse" to "Auxiliary Nurses",
        "non_nursing_staff" to "Non Nursing Staff", "paramedical_staff" to "Paramedical Staff",
        "others" to "Others",
    )
}

object RequirementDuration {
    val displayNames = mapOf(
        "short_term" to "Short Term (Few Days/Weeks Only)", "long_term" to "Long Term",
    )
}

object DocumentType {
    const val QUALIFICATION = "qualification"
    const val AADHAAR = "aadhaar"
    const val OTHER = "other"
}

/** Mirrors Validation from packages/shared-constants/src/validation.ts. */
object Validation {
    val PHONE_REGEX = Regex("^[6-9]\\d{9}$") // the local 10-digit part; +91 prefix is added separately
    val NAME_REGEX = Regex("^[a-zA-Z\\s]+$")
    const val NAME_MAX_LENGTH = 24
    val CODE_REGEX = Regex("^\\d{4}$")
    const val AGE_MIN = 18
    const val AGE_MAX = 65
    const val APPLY_BY_WINDOW_DAYS_DEFAULT = 3
}
