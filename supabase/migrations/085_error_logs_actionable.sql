-- Make Error Logs actionable: an admin should be able to see WHAT the user
-- was doing when it broke, call the people it happened to, and record that
-- it was dealt with.
--
-- request_context: the sanitized request that triggered the error —
--   { query, params, body } — with anything secret-shaped (PINs/codes,
--   passwords, tokens, OTPs, authorization) replaced by "[redacted]" and
--   long values/arrays/depth truncated before it is stored (see
--   sanitizeRequestContext). Phone numbers and the rest of the business
--   payload are kept on purpose: that is the "real data" an admin needs to
--   reproduce or fix the problem. Rows are still purged after 7 days.
-- user_agent: which client sent it (the Dart HTTP client for the app, a
--   browser for admin-web).
-- status/resolved_*/resolution_note: open -> resolved workflow so a handled
--   error (e.g. "called the patient, re-registered them") stops showing up
--   as work to do. Existing rows start as 'open'.

ALTER TABLE error_logs
  ADD COLUMN IF NOT EXISTS request_context JSONB,
  ADD COLUMN IF NOT EXISTS user_agent TEXT,
  ADD COLUMN IF NOT EXISTS status VARCHAR(10) NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'resolved')),
  ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS resolved_by UUID REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS resolution_note TEXT;

CREATE INDEX IF NOT EXISTS idx_error_logs_status_created ON error_logs(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_error_logs_user_status ON error_logs(user_id, status);

-- Resolving an error is an admin action, audit-logged like resolving a
-- support ticket.
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
    'error_log_resolved'
  ));
