export const VerificationStatus = {
  PENDING_CALL: 'pending_call',
  AVAILABLE: 'available',
  UNAVAILABLE: 'unavailable',
  ASSIGNED: 'assigned',
  REJECTED: 'rejected',
} as const;
export type VerificationStatus = (typeof VerificationStatus)[keyof typeof VerificationStatus];

export const JobStatus = {
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

export const Mobility = {
  WALKS_INDEPENDENTLY: 'walks_independently',
  WALKS_WITH_ASSISTANCE: 'walks_with_assistance',
  USES_WALKER: 'uses_walker',
  USES_WHEELCHAIR: 'uses_wheelchair',
  BEDRIDDEN: 'bedridden',
} as const;
export type Mobility = (typeof Mobility)[keyof typeof Mobility];

export const Communication = {
  VERBAL: 'verbal',
  DIFFICULTY_COMMUNICATING: 'difficulty_communicating',
  SIGN_LANGUAGE: 'sign_language',
} as const;
export type Communication = (typeof Communication)[keyof typeof Communication];

export const FeedingType = {
  ORAL_INDEPENDENT: 'oral_independent',
  ORAL_NEEDS_ASSISTANCE: 'oral_needs_assistance',
  TUBE_FEEDING: 'tube_feeding',
  ORAL_AND_TUBE: 'oral_and_tube',
} as const;
export type FeedingType = (typeof FeedingType)[keyof typeof FeedingType];

export const MedicalAssistance = {
  MEDICATION_REMINDERS: 'medication_reminders',
  MEDICATION_ADMINISTRATION: 'medication_administration',
  INSULIN_ADMINISTRATION: 'insulin_administration',
  OTHER_INJECTIONS: 'other_injections',
  OTHER: 'other',
} as const;
export type MedicalAssistance = (typeof MedicalAssistance)[keyof typeof MedicalAssistance];

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
  OTHER: 'other',
} as const;
export type MedicalCondition = (typeof MedicalCondition)[keyof typeof MedicalCondition];

export const ToiletAssistance = {
  USES_DIAPERS: 'uses_diapers',
  USES_BED_PAN: 'uses_bed_pan',
  USES_CATHETER: 'uses_catheter',
  COMPLETE_ASSISTANCE: 'complete_toileting_assistance',
  OTHERS: 'others',
  INDEPENDENT: 'independent',
} as const;
export type ToiletAssistance = (typeof ToiletAssistance)[keyof typeof ToiletAssistance];

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
  APP_VERSION_UPDATED: 'app_version_updated',
} as const;
export type AuditAction = (typeof AuditAction)[keyof typeof AuditAction];

export const AppPlatform = {
  ANDROID: 'android',
  IOS: 'ios',
} as const;
export type AppPlatform = (typeof AppPlatform)[keyof typeof AppPlatform];

export const UserRole = {
  SUPER_ADMIN: 'super_admin',
  ADMIN: 'admin',
  CAREGIVER: 'caregiver',
} as const;
export type UserRole = (typeof UserRole)[keyof typeof UserRole];

export const DocumentType = {
  QUALIFICATION: 'qualification',
  AADHAAR: 'aadhaar',
  OTHER: 'other',
} as const;
export type DocumentType = (typeof DocumentType)[keyof typeof DocumentType];
