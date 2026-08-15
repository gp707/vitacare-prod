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

export const JobResponse = {
  ACCEPTED: 'accepted',
  REJECTED: 'rejected',
  MORE_DETAILS: 'more_details',
} as const;
export type JobResponse = (typeof JobResponse)[keyof typeof JobResponse];

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

export const ServiceMode = {
  TWENTY_FOUR_HRS_LIVE_IN: '24hrs_live_in',
  TWELVE_HRS_PG: '12hrs_pg',
} as const;
export type ServiceMode = (typeof ServiceMode)[keyof typeof ServiceMode];

export const Religion = {
  HINDU: 'hindu',
  MUSLIM: 'muslim',
  CHRISTIAN: 'christian',
  OTHERS: 'others',
} as const;
export type Religion = (typeof Religion)[keyof typeof Religion];

export const WorkType = {
  COMPANION_CARE: 'companion_care',
  BEDSIDE_CARE: 'bedside_care',
  CRITICAL_CARE: 'critical_care',
} as const;
export type WorkType = (typeof WorkType)[keyof typeof WorkType];

export const SalaryRanges = {
  COMPANION_CARE: { min: 25000, max: 30000 },
  BEDSIDE_CARE: { min: 28000, max: 35000 },
  CRITICAL_CARE: { min: 30000, max: 45000 },
} as const;

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
  ADMIN_DOCUMENT_UPLOADED: 'admin_document_uploaded',
  ADMIN_ROLE_CHANGED: 'admin_role_changed',
  ADMIN_ACTIVATED: 'admin_activated',
  JOB_REMINDER_SENT: 'job_reminder_sent',
} as const;
export type AuditAction = (typeof AuditAction)[keyof typeof AuditAction];

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
