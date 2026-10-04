export const VerificationStatus = {
  PENDING_CALL: 'pending_call',
  AVAILABLE: 'available',
  UNAVAILABLE: 'unavailable',
  ASSIGNED: 'assigned',
  REJECTED: 'rejected',
} as const;
export type VerificationStatus = (typeof VerificationStatus)[keyof typeof VerificationStatus];

export const JobStatus = {
  // A NurseNow individual-posted job sits here until an admin approves
  // (-> active, setting frequency_of_care/salary_amount) or rejects
  // (-> closed, with rejection_reason). Admin's own postings skip this
  // entirely — created straight into active, same as before.
  PENDING_REVIEW: 'pending_review',
  ACTIVE: 'active',
  CLOSED: 'closed',
} as const;
export type JobStatus = (typeof JobStatus)[keyof typeof JobStatus];

export const JobApplicationStatus = {
  APPLIED: 'applied',
  REJECTED: 'rejected',
  ACCEPTED: 'accepted',
  COMPLETED: 'completed',
} as const;
export type JobApplicationStatus = (typeof JobApplicationStatus)[keyof typeof JobApplicationStatus];

export const Gender = {
  MALE: 'male',
  FEMALE: 'female',
  OTHER: 'other',
} as const;
export type Gender = (typeof Gender)[keyof typeof Gender];

export const Language = {
  HINDI: 'hindi',
  ENGLISH: 'english',
  KANNADA: 'kannada',
  TAMIL: 'tamil',
  TELUGU: 'telugu',
  MALAYALAM: 'malayalam',
  BENGALI: 'bengali',
  GUJARATI: 'gujarati',
  MARATHI: 'marathi',
} as const;
export type Language = (typeof Language)[keyof typeof Language];

export const Religion = {
  HINDU: 'hindu',
  MUSLIM: 'muslim',
  CHRISTIAN: 'christian',
  OTHERS: 'others',
} as const;
export type Religion = (typeof Religion)[keyof typeof Religion];

export const DutyType = {
  DAY_DUTY: 'day_duty',
  NIGHT_DUTY: 'night_duty',
  LIVE_IN: 'live_in',
} as const;
export type DutyType = (typeof DutyType)[keyof typeof DutyType];

export const FrequencyOfCare = {
  DAILY: 'daily',
  MONTHLY: 'monthly',
} as const;
export type FrequencyOfCare = (typeof FrequencyOfCare)[keyof typeof FrequencyOfCare];

/** How long the engagement is expected to last — collected on NurseNow
 *  individual postings only (see CLAUDE.md); nullable on `jobs` since
 *  admin-posted jobs and pre-existing rows never set it. */
export const CareDuration = {
  FEW_DAYS: 'few_days',
  FEW_WEEKS: 'few_weeks',
  FEW_MONTHS: 'few_months',
  LONG_TERM: 'long_term',
} as const;
export type CareDuration = (typeof CareDuration)[keyof typeof CareDuration];

export const FeedingType = {
  ORAL_FEEDING: 'oral_feeding',
  TUBE_FEEDING: 'tube_feeding',
  OTHERS: 'others',
} as const;
export type FeedingType = (typeof FeedingType)[keyof typeof FeedingType];

export const MedicalCondition = {
  CANCER: 'cancer',
  STROKE: 'stroke',
  BRAIN_INJURY: 'brain_injury',
  DEMENTIA_ALZHEIMERS: 'dementia_alzheimers',
  PARKINSONS: 'parkinsons',
  HEART_CONDITION: 'heart_condition',
  KIDNEY_DISEASE_DIALYSIS: 'kidney_disease_dialysis',
  DIABETES: 'diabetes',
  COLOSTOMY: 'colostomy',
  PARALYSIS: 'paralysis',
  TB: 'tb',
  BP: 'bp',
  OXYGEN_SUPPORT: 'oxygen_support',
  INSULIN_ADMINISTRATION_SUPPORT: 'insulin_administration_support',
  INJECTION_SUPPORT: 'injection_support',
  CANNULA_CARE: 'cannula_care',
  CATHETER_CARE: 'catheter_care',
  NEBULISATION_SUPPORT: 'nebulisation_support',
  OTHER: 'other',
} as const;
export type MedicalCondition = (typeof MedicalCondition)[keyof typeof MedicalCondition];

export const ToiletAssistance = {
  INDEPENDENT: 'independent',
  DIAPERS_BEDSIDE_SUPPORT: 'diapers_bedside_support',
  USES_CATHETER: 'uses_catheter',
  OTHERS: 'others',
} as const;
export type ToiletAssistance = (typeof ToiletAssistance)[keyof typeof ToiletAssistance];

/** A caregiver's own reason for closing an accepted job/requirement
 *  (POST .../complete) — a fixed dropdown, visible to both the caregiver
 *  themselves and the job/requirement poster. Defaults to NO_REASON when
 *  the caregiver submits without picking anything else. */
export const CaregiverCloseReason = {
  DUTY_COMPLETE: 'duty_complete',
  NO_REASON: 'no_reason',
  DID_NOT_LIKE_WORK: 'did_not_like_work',
  TEMPORARILY_NOT_AVAILABLE: 'temporarily_not_available',
  FAMILY_PROBLEMS: 'family_problems',
  NEED_TO_GO_HOMETOWN: 'need_to_go_hometown',
} as const;
export type CaregiverCloseReason = (typeof CaregiverCloseReason)[keyof typeof CaregiverCloseReason];

export const VitalMonitoringType = {
  BLOOD_PRESSURE: 'blood_pressure',
  BLOOD_SUGAR: 'blood_sugar',
  OXYGEN_SPO2: 'oxygen_spo2',
  TEMPERATURE: 'temperature',
  PULSE: 'pulse',
  OTHER: 'other',
} as const;
export type VitalMonitoringType = (typeof VitalMonitoringType)[keyof typeof VitalMonitoringType];

export const City = {
  BANGALORE: 'bangalore',
  MUMBAI: 'mumbai',
  HYDERABAD: 'hyderabad',
  CHENNAI: 'chennai',
  PUNE: 'pune',
  DELHI: 'delhi',
  GURGAON: 'gurgaon',
} as const;
export type City = (typeof City)[keyof typeof City];

export const Qualification = {
  RN_ABOVE_2_YEARS: 'rn_above_2_years',
  RN_BELOW_2_YEARS: 'rn_below_2_years',
  REGISTERED_RECENTLY: 'registered_recently',
  BSC_GNM_UNREGISTERED: 'bsc_gnm_unregistered',
  ANM_STUDENT_BACKLOG: 'anm_student_backlog',
  GDA_NON_NURSING: 'gda_non_nursing',
} as const;
export type Qualification = (typeof Qualification)[keyof typeof Qualification];

export const AuditAction = {
  REGISTRATION: 'registration',
  LOGIN: 'login',
  PROFILE_UPDATED: 'profile_updated',
  STATUS_CHANGED: 'status_changed',
  CODE_CHANGED: 'code_changed',
  ADMIN_EDIT_PROFILE: 'admin_edit_profile',
  ADMIN_NOTE_ADDED: 'admin_note_added',
  ADMIN_CREATED: 'admin_created',
  ADMIN_DEACTIVATED: 'admin_deactivated',
  PHONE_CHANGED: 'phone_changed',
  EDITS_ACKNOWLEDGED: 'edits_acknowledged',
  JOB_POSTED: 'job_posted',
  JOB_CLOSED: 'job_closed',
  JOB_RESPONSE: 'job_response',
  JOB_APPLICATION_DECIDED: 'job_application_decided',
  ADMIN_DOCUMENT_UPLOADED: 'admin_document_uploaded',
  ADMIN_ROLE_CHANGED: 'admin_role_changed',
  ADMIN_ACTIVATED: 'admin_activated',
  JOB_REMINDER_SENT: 'job_reminder_sent',
  JOB_UPDATED: 'job_updated',
  JOB_COMPLETED: 'job_completed',
  JOB_REAPPLIED: 'job_reapplied',
  APP_VERSION_UPDATED: 'app_version_updated',
  // NurseNow Organisation phase — kept distinct from job_* even though the
  // shape mirrors it, since organisation_requirements is a separate table
  // from jobs (see migration 041).
  ORG_REQUIREMENT_POSTED: 'org_requirement_posted',
  ORG_REQUIREMENT_UPDATED: 'org_requirement_updated',
  ORG_REQUIREMENT_REJECTED: 'org_requirement_rejected',
  ORG_REQUIREMENT_APPLICATION_DECIDED: 'org_requirement_application_decided',
  OTP_SETTING_UPDATED: 'otp_setting_updated',
  RATE_CARD_UPDATED: 'rate_card_updated',
  SCOPE_OF_WORK_UPDATED: 'scope_of_work_updated',
  DUTY_REQUIREMENTS_UPDATED: 'duty_requirements_updated',
  JOB_SETTINGS_UPDATED: 'job_settings_updated',
  ADMIN_PASSWORD_CHANGED: 'admin_password_changed',
  INDIVIDUAL_MESSAGE_CREATED: 'individual_message_created',
  INDIVIDUAL_MESSAGE_UPDATED: 'individual_message_updated',
  INDIVIDUAL_MESSAGE_DELETED: 'individual_message_deleted',
  CAREGIVER_MESSAGE_CREATED: 'caregiver_message_created',
  CAREGIVER_MESSAGE_UPDATED: 'caregiver_message_updated',
  CAREGIVER_MESSAGE_DELETED: 'caregiver_message_deleted',
  AUDIT_LOG_RETENTION_UPDATED: 'audit_log_retention_updated',
  AUDIT_LOGS_PURGED: 'audit_logs_purged',
  APP_MAINTENANCE_UPDATED: 'app_maintenance_updated',
  JOBS_BULK_DELETED: 'jobs_bulk_deleted',
  ADMIN_DOCUMENT_VERSION_DELETED: 'admin_document_version_deleted',
  // Admin-initiated PIN/code reset — distinct from a caregiver/individual/
  // organisation's own self-service CODE_CHANGED.
  ADMIN_CODE_RESET: 'admin_code_reset',
  PUSH_NOTIFICATION_CREATED: 'push_notification_created',
  PUSH_NOTIFICATION_CANCELLED: 'push_notification_cancelled',
} as const;
export type AuditAction = (typeof AuditAction)[keyof typeof AuditAction];

// When each individual_messages row is shown on NurseNow's Messages tab —
// picked by admin per message, evaluated client-side against the
// individual's own already-fetched requirement data (see
// apps/justheal-app/lib/patient_hospital/features/individual/data/requirement_messages.dart).
export const MessageEvent = {
  WELCOME: 'welcome',
  REQUIREMENT_LIVE: 'requirement_live',
  REQUIREMENT_CARE_TIER: 'requirement_care_tier',
  // Evaluated against the account's most recently posted requirement's
  // applications (any status present on it, regardless of the
  // requirement's own status — acceptance closes the requirement, so
  // caregiverAccepted/caregiverClosed can never coincide with a still-
  // "live" requirement). Fires once per matching applicant, not once per
  // requirement — message text may contain the literal token
  // "{caregiver_name}", substituted with that specific applicant's name.
  // Not mutually exclusive with each other or with
  // requirementLive/requirementCareTier — e.g. a still-live requirement
  // can simultaneously have other applied-but-undecided candidates.
  CAREGIVER_APPLIED: 'caregiver_applied',
  CAREGIVER_ACCEPTED: 'caregiver_accepted',
  CAREGIVER_REJECTED: 'caregiver_rejected',
  CAREGIVER_CLOSED: 'caregiver_closed',
} as const;
export type MessageEvent = (typeof MessageEvent)[keyof typeof MessageEvent];

// A curated, bounded set of icon keys an admin can pick per message —
// never free text, so a bad value can't crash the client. Keys match
// their corresponding Flutter Icons.* constant name.
export const MessageIcon = {
  EDIT_NOTE: 'edit_note',
  RULE: 'rule',
  TRAVEL_EXPLORE: 'travel_explore',
  WAVING_HAND: 'waving_hand',
  ROCKET_LAUNCH: 'rocket_launch',
  FAVORITE: 'favorite',
  MEDICAL_SERVICES: 'medical_services',
  EMERGENCY: 'emergency',
  INFO: 'info',
  CELEBRATION: 'celebration',
  PERSON_ADD: 'person_add',
  CHECK_CIRCLE: 'check_circle',
  CANCEL: 'cancel',
  TASK_ALT: 'task_alt',
} as const;
export type MessageIcon = (typeof MessageIcon)[keyof typeof MessageIcon];

// When each caregiver_messages row is shown on NurseJobs (caregiver-app)'s
// Messages bell — the caregiver-side counterpart to MessageEvent, evaluated
// against the caregiver's own application lifecycle instead of an
// Individual's posted requirement (see resolveCaregiverMessages() in
// apps/justheal-app/lib/caregiver/features/jobs/data/caregiver_messages_logic.dart).
// Reuses MessageIcon for icon selection — no separate icon enum needed.
export const CaregiverMessageEvent = {
  // Caregiver has never applied to any job yet.
  WELCOME: 'welcome',
  // A currently-active job (GET /caregiver/jobs) has
  // my_application.status == 'applied'.
  JOB_APPLIED: 'job_applied',
  // An assigned job (GET /caregiver/jobs/assigned, durable regardless of
  // the job's own status) has my_application.status == 'accepted'.
  JOB_ACCEPTED: 'job_accepted',
  // A currently-active job has my_application.status == 'rejected'.
  JOB_REJECTED: 'job_rejected',
  // An assigned job has my_application.status == 'completed' — a
  // caregiver-initiated close of an accepted job (matches the "Close"
  // terminology already used in caregiver-app's own MyJobs UI).
  JOB_CLOSED: 'job_closed',
} as const;
export type CaregiverMessageEvent = (typeof CaregiverMessageEvent)[keyof typeof CaregiverMessageEvent];

export const AppPlatform = {
  ANDROID: 'android',
  IOS: 'ios',
} as const;
export type AppPlatform = (typeof AppPlatform)[keyof typeof AppPlatform];

export const UserRole = {
  SUPER_ADMIN: 'super_admin',
  ADMIN: 'admin',
  CAREGIVER: 'caregiver',
  // NurseNow patient/family account.
  INDIVIDUAL: 'individual',
  // NurseNow hospital/rehab/clinic account.
  ORGANISATION: 'organisation',
} as const;
export type UserRole = (typeof UserRole)[keyof typeof UserRole];

export const OrganisationType = {
  HOSPITAL: 'hospital',
  REHAB: 'rehab',
  CLINIC: 'clinic',
  AGENCY: 'agency',
} as const;
export type OrganisationType = (typeof OrganisationType)[keyof typeof OrganisationType];

/** How long an organisation requirement's engagement is expected to run —
 *  org-set at creation, alongside type_of_nurse/number_of_vacancies/
 *  preferred_gender. Distinct from Individual's 4-value CareDuration. */
export const RequirementDuration = {
  SHORT_TERM: 'short_term',
  LONG_TERM: 'long_term',
} as const;
export type RequirementDuration = (typeof RequirementDuration)[keyof typeof RequirementDuration];

// Distinct from Qualification (a caregiver's own self-reported
// credential) — this is the category an organisation requests when
// posting a requirement. Replaced wholesale (2026-08-19) with the
// hospital-facing category list actually used by admin — validated at
// the DTO layer (@IsIn), not a DB CHECK, so this can change without a
// migration.
export const TypeOfNurse = {
  REGISTERED_NURSE: 'registered_nurse',
  NURSING_COMPLETED: 'nursing_completed',
  NURSING_STUDENT: 'nursing_student',
  AUXILIARY_NURSE: 'auxiliary_nurse',
  NON_NURSING_STAFF: 'non_nursing_staff',
  PARAMEDICAL_STAFF: 'paramedical_staff',
  OTHERS: 'others',
} as const;
export type TypeOfNurse = (typeof TypeOfNurse)[keyof typeof TypeOfNurse];

// Which app is calling POST /auth/login/code — phone is unique per app
// bucket, not globally (migration 045), so the backend needs to know
// which bucket to look the phone up in: NURSEJOBS -> role=caregiver only,
// NURSENOW -> role IN (individual, organisation). Neither caregiver-app
// nor nursenow-app knows the other's account state, so this is purely a
// "which app am I" flag, not a specific role choice.
export const LoginApp = {
  NURSEJOBS: 'nursejobs',
  NURSENOW: 'nursenow',
} as const;
export type LoginApp = (typeof LoginApp)[keyof typeof LoginApp];

// Scopes an OTP send/verify to what it's proving — a register OTP can never
// be replayed to satisfy a login, and vice versa.
export const OtpPurpose = {
  REGISTER: 'register',
  LOGIN: 'login',
} as const;
export type OtpPurpose = (typeof OtpPurpose)[keyof typeof OtpPurpose];

// organisation_profiles.city is validated against City.all plus this one
// extra sentinel — a separate org-scoped list, not an extension of the
// shared City enum (which stays caregiver/job-scoped, used for filtering
// elsewhere that 'others' would break).
export const ORGANISATION_CITY_OTHERS = 'others';

// organisation_requirements.status reuses JobStatus's exact 3 values
// (pending_review/active/closed) — same admin-approval lifecycle, just a
// separate table. organisation_requirement_applications.status likewise
// reuses JobApplicationStatus (applied/rejected/accepted/completed).

// Admin-composed bulk push notification (apps/api/src/admin-push-notifications/)
// — pending until scheduled_at, then sent (or failed) by the minute-poll
// cron in AdminPushNotificationsService. cancelled is only reachable from
// pending (a future-scheduled one not yet sent).
export const PushNotificationStatus = {
  PENDING: 'pending',
  SENT: 'sent',
  FAILED: 'failed',
  CANCELLED: 'cancelled',
} as const;
export type PushNotificationStatus = (typeof PushNotificationStatus)[keyof typeof PushNotificationStatus];

export const DocumentType = {
  QUALIFICATION: 'qualification',
  AADHAAR: 'aadhaar',
  OTHER: 'other',
} as const;
export type DocumentType = (typeof DocumentType)[keyof typeof DocumentType];
