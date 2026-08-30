-- Caregivers can now re-apply to a job they previously rejected, as long as
-- the job is still active (GET /caregiver/jobs only ever returns active
-- jobs, so re-apply is naturally only reachable while it's live). A fresh
-- 'applied' upsert already clears rejected_at, which would otherwise erase
-- the fact a rejection ever happened — this timestamp preserves it so the
-- caregiver's own history and the patient/employer's applicant view can
-- show "Re-applied: <date>" instead of the rejection silently vanishing.
ALTER TABLE job_applications ADD COLUMN reapplied_at TIMESTAMPTZ;

ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'job_application_decided', 'admin_document_uploaded', 'admin_role_changed',
    'admin_activated', 'job_reminder_sent', 'job_updated', 'job_completed',
    'app_version_updated', 'org_requirement_posted', 'org_requirement_updated',
    'org_requirement_rejected', 'org_requirement_application_decided',
    'otp_setting_updated', 'job_reapplied'
  ));
