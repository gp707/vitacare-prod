-- Leave days and salary pauses for an accepted caregiver (set by the patient/family).
--
--   job_application_leaves  one row per day marked as leave; the patient can cancel a day.
--   job_application_pauses  "salary paused" periods. Every day from paused_from until the
--                           day it is resumed (resumed_on, exclusive) counts as leave, so the
--                           pay for that stretch is left out. resumed_on IS NULL = still paused.
--
-- Both belong to one application (one caregiver on one job): they go when the application is
-- decided again (re-accepted / rejected) — see JobApplicationsRepository.decide — or when the
-- application row is deleted (ON DELETE CASCADE).
--
-- Additive: safe to apply before the backend that uses it is deployed.

CREATE TABLE IF NOT EXISTS job_application_leaves (
  application_id UUID NOT NULL REFERENCES job_applications(id) ON DELETE CASCADE,
  leave_date     DATE NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (application_id, leave_date)
);

CREATE TABLE IF NOT EXISTS job_application_pauses (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES job_applications(id) ON DELETE CASCADE,
  paused_from    DATE NOT NULL,
  resumed_on     DATE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (resumed_on IS NULL OR resumed_on >= paused_from)
);

CREATE INDEX IF NOT EXISTS idx_job_application_pauses_app ON job_application_pauses (application_id);
-- At most one pause can be open (not yet resumed) per application.
CREATE UNIQUE INDEX IF NOT EXISTS uq_job_application_pauses_open
  ON job_application_pauses (application_id) WHERE resumed_on IS NULL;

-- Leave/pause changes are audit-logged ('job_leave_updated').
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'job_application_decided', 'admin_document_uploaded', 'admin_role_changed',
    'admin_activated', 'job_reminder_sent', 'job_updated', 'job_completed', 'job_reapplied',
    'app_version_updated', 'org_requirement_posted', 'org_requirement_updated',
    'org_requirement_rejected', 'org_requirement_application_decided',
    'otp_setting_updated', 'rate_card_updated', 'scope_of_work_updated',
    'duty_requirements_updated', 'job_settings_updated', 'admin_password_changed',
    'individual_message_created', 'individual_message_updated', 'individual_message_deleted',
    'caregiver_message_created', 'caregiver_message_updated', 'caregiver_message_deleted',
    'audit_log_retention_updated', 'audit_logs_purged', 'app_maintenance_updated',
    'jobs_bulk_deleted', 'admin_document_version_deleted', 'admin_code_reset',
    'push_notification_created', 'push_notification_cancelled',
    'support_ticket_created', 'support_ticket_resolved', 'account_deleted',
    'error_log_resolved', 'job_agreement_set', 'job_leave_updated'
  ));
