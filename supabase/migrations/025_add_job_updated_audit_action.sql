-- ============================================
-- New audit action for the admin job-edit/repost feature
-- (PATCH /admin/jobs/:id).
-- ============================================

ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'call_verified', 'advanced_details_submitted',
    'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'job_application_decided',
    'admin_document_uploaded', 'admin_role_changed', 'admin_activated', 'job_reminder_sent',
    'job_updated'
  ));
