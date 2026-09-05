/// Mirrors packages/shared-constants/src/validation.ts.
class Validation {
  static final RegExp phoneRegex = RegExp(r'^\+91[6-9]\d{9}$');
  static final RegExp nameRegex = RegExp(r'^[a-zA-Z\s]+$');
  static const nameMaxLength = 100;
  static const codeLength = 4;
  static final RegExp codeRegex = RegExp(r'^\d{4}$');
  static const otpLength = 6;
  static final RegExp otpRegex = RegExp(r'^\d{6}$');
  static const ageMin = 18;
  static const ageMax = 65;
  static const rejectionMessageMaxLength = 1000;
  static const fileMaxSizeBytes = 10 * 1024 * 1024;
  // How long a job stays within its caregiver-facing "apply-by" urgency
  // window (see JobModel.applyByDate/daysLeftToApply) — purely
  // informational, never blocks applying or auto-closes the job. Also the
  // default threshold for admin-web's "posted more than N days ago" Jobs
  // filter, which finds jobs that have fallen out of this window and may
  // need manual attention.
  static const applyByWindowDays = 3;
  // Display-only convenience derived from fileMaxSizeBytes — shown to the
  // user wherever a document/photo picker is offered, so the client-side
  // limit is never a hardcoded number out of sync with the actual check.
  static const fileMaxSizeMb = fileMaxSizeBytes ~/ (1024 * 1024);
  static const maxOtherDocuments = 3;
  static const paginationDefaultLimit = 20;
  static const paginationMaxLimit = 100;
  static const passwordMinLength = 6;
  // Hard cap on one admin-web "bulk delete" call (jobs + organisation
  // requirements combined) — a safety guardrail against an accidentally
  // too-broad "select all matching filter" wiping out far more than
  // intended in one irreversible action. An admin who genuinely needs to
  // delete more narrows their filter and repeats.
  static const bulkDeleteMaxItems = 500;
}
