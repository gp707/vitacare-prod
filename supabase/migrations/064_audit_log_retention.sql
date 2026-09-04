-- Admin-configurable audit-log retention. audit_logs has grown unbounded
-- since it was created (migration 010) — this adds a singleton settings row
-- (same convention as job_settings/duty_requirements/rate_card: id fixed to
-- 1 by a DB CHECK) holding how many days of audit_logs to keep live, plus a
-- daily @Cron sweep (AuditLogRetentionService.purgeExpiredLogs, mirroring
-- FcmService's existing daily 8 AM IST job) that hard-deletes anything
-- older than that window. Deliberately a straight delete, no export/backup
-- step — confirmed with the user, not a partial implementation.
CREATE TABLE audit_log_retention_settings (
  id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  retention_days INTEGER NOT NULL DEFAULT 180 CHECK (retention_days > 0),
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO audit_log_retention_settings (id, retention_days) VALUES (1, 180);

-- Widen the audit_logs action CHECK constraint for the 2 new action values
-- (retention setting changed by an admin; the sweep itself running),
-- preserving every existing value (verified against the live DB's actual
-- current constraint, matching 063's own note on doing the same).
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
    'audit_log_retention_updated', 'audit_logs_purged'
  ));
