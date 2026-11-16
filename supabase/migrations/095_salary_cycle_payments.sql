-- Salary is paid every 14 days (a "cycle"), counted from the agreed cycle start date.
-- When the patient/family marks a cycle as paid, this row freezes what that cycle was:
-- its dates, the rate that applied, the leave days inside it, the days worked and the
-- amount, plus the date it was paid. Later changes to the rate, start date or leave days
-- never rewrite a paid cycle. Cycles not yet paid are worked out on the fly (see
-- apps/api/src/common/salary-cycles.ts), so no rows exist for them.
--
-- Additive: safe to apply before the backend that uses it is deployed.

CREATE TABLE IF NOT EXISTS salary_cycle_payments (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES job_applications(id) ON DELETE CASCADE,
  cycle_start    DATE NOT NULL,
  cycle_end      DATE NOT NULL,
  rate           INTEGER NOT NULL CHECK (rate > 0),
  rate_unit      VARCHAR(10) NOT NULL CHECK (rate_unit IN ('daily', 'monthly')),
  leave_dates    JSONB NOT NULL DEFAULT '[]'::jsonb,
  worked_days    INTEGER NOT NULL CHECK (worked_days >= 0),
  amount         INTEGER NOT NULL CHECK (amount >= 0),
  paid_on        DATE NOT NULL,
  marked_by      UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (cycle_end >= cycle_start),
  UNIQUE (application_id, cycle_start)
);

CREATE INDEX IF NOT EXISTS idx_salary_cycle_payments_app ON salary_cycle_payments (application_id, cycle_start);

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
    'error_log_resolved', 'job_agreement_set', 'job_leave_updated', 'job_salary_paid'
  ));
