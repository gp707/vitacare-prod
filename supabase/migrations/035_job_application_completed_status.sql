-- Caregivers can now hold multiple concurrent accepted jobs. Each one needs
-- its own explicit "I finished this job" action, distinct from being
-- rejected/undone by an admin — so a job_application gains a fourth
-- terminal status, 'completed', alongside a completed_at timestamp
-- (mirrors the existing applied_at/accepted_at/rejected_at per-transition
-- columns). 'accepted' remains the active/in-progress state.
ALTER TABLE job_applications ADD COLUMN completed_at TIMESTAMPTZ;

ALTER TABLE job_applications DROP CONSTRAINT job_applications_status_check;
ALTER TABLE job_applications ADD CONSTRAINT job_applications_status_check
  CHECK (status IN ('applied', 'rejected', 'accepted', 'completed'));

ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'call_verified', 'advanced_details_submitted',
    'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'job_application_decided',
    'admin_document_uploaded', 'admin_role_changed', 'admin_activated', 'job_reminder_sent',
    'job_updated', 'app_version_updated', 'job_completed'
  ));
