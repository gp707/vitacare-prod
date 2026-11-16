-- Feedback between a patient/family and a caregiver, once they have actually worked together.
-- One row per person per engagement (one caregiver on one job = one job_applications row):
-- the patient's feedback about the caregiver and the caregiver's feedback about the family are
-- two rows. Write once and final: no edit, no delete (the UNIQUE key refuses a second one).
-- Whether someone may write is decided by the API (accepted + the agreed cycle start date has
-- arrived), never by this table.
--
-- Additive: safe to apply before the backend that uses it is deployed.

CREATE TABLE IF NOT EXISTS engagement_feedback (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES job_applications(id) ON DELETE CASCADE,
  author_role    VARCHAR(12) NOT NULL CHECK (author_role IN ('individual', 'caregiver')),
  author_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  about_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rating         SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment        TEXT CHECK (comment IS NULL OR char_length(comment) <= 200),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (application_id, author_role)
);

CREATE INDEX IF NOT EXISTS idx_engagement_feedback_about ON engagement_feedback (about_user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_engagement_feedback_created ON engagement_feedback (created_at DESC);

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
    'error_log_resolved', 'job_agreement_set', 'job_leave_updated', 'job_salary_paid', 'feedback_submitted'
  ));
