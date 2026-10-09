-- Self-service account deletion (caregiver/individual/organisation).
-- Deletion anonymizes the users row in place (phone/full_name/email/
-- code_hash/fcm_token) and deactivates it, rather than removing the row —
-- other people's own records (job_applications, audit_logs, admin notes,
-- support_tickets) reference it, and a hard delete would either orphan
-- those or cascade-destroy data that belongs to someone else's account.
-- deleted_at marks when this happened, distinct from is_active (which
-- also covers an ordinary admin deactivation with no anonymization).
ALTER TABLE users ADD COLUMN deleted_at TIMESTAMPTZ;

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
    'support_ticket_created', 'support_ticket_resolved', 'account_deleted'
  ));
