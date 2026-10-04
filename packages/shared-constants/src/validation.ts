export const Validation = {
  PHONE_REGEX: /^\+91[6-9]\d{9}$/,
  NAME_REGEX: /^[a-zA-Z\s]+$/,
  NAME_MAX_LENGTH: 24,
  CODE_LENGTH: 4,
  CODE_REGEX: /^\d{4}$/,
  OTP_LENGTH: 6,
  OTP_REGEX: /^\d{6}$/,
  OTP_EXPIRY_MINUTES: 5,
  OTP_MAX_ATTEMPTS: 5,
  OTP_RESEND_COOLDOWN_SECONDS: 30,
  OTP_MAX_SENDS_PER_WINDOW: 5,
  OTP_SEND_WINDOW_MINUTES: 60,
  AGE_MIN: 18,
  AGE_MAX: 65,
  REJECTION_MESSAGE_MAX_LENGTH: 1000,
  // A NurseNow organisation's own "Special Skills Required" field on a
  // requirement posting — a large plain-text textarea. Originally capped at
  // 256, which was cutting off real-world pasted text (e.g. copied from
  // WhatsApp/Word); raised to match REJECTION_MESSAGE_MAX_LENGTH so a
  // realistic paragraph of pasted text fits without silent truncation.
  SPECIAL_SKILLS_MAX_LENGTH: 1000,
  FILE_MAX_SIZE_BYTES: 10 * 1024 * 1024,
  // How long a job stays within its caregiver-facing "apply-by" urgency
  // window (see JobModel.applyByDate/daysLeftToApply) — purely
  // informational, never blocks applying or auto-closes the job. Also the
  // default threshold for admin-web's "posted more than N days ago" Jobs
  // filter (ListJobsQueryDto.posted_more_than_days_ago), which finds jobs
  // that have fallen out of this window and may need manual attention.
  APPLY_BY_WINDOW_DAYS: 3,
  MAX_OTHER_DOCUMENTS: 3,
  PAGINATION_DEFAULT_LIMIT: 20,
  PAGINATION_MAX_LIMIT: 100,
  PASSWORD_MIN_LENGTH: 6,
  // Hard cap on one admin-web "bulk delete" call (jobs + organisation
  // requirements combined) — a safety guardrail against an accidentally
  // too-broad "select all matching filter" wiping out far more than
  // intended in one irreversible action. An admin who genuinely needs to
  // delete more narrows their filter and repeats.
  BULK_DELETE_MAX_ITEMS: 500,
  // Same reasoning as BULK_DELETE_MAX_ITEMS — a safety guardrail on one
  // admin-composed push notification's recipient list.
  PUSH_NOTIFICATION_MAX_RECIPIENTS: 5000,
  PUSH_NOTIFICATION_TITLE_MAX_LENGTH: 100,
  PUSH_NOTIFICATION_BODY_MAX_LENGTH: 500,
} as const;
