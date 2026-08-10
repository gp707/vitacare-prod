-- ============================================
-- Add 'admin_document_uploaded' to audit_logs.action CHECK constraint
-- (admin uploading/replacing a caregiver's selfie/qualification/aadhaar/
-- other document from the admin dashboard)
-- ============================================
ALTER TABLE audit_logs DROP CONSTRAINT audit_logs_action_check;

ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check CHECK (action IN (
  'registration',
  'login',
  'call_verified',
  'advanced_details_submitted',
  'profile_updated',
  'status_changed',
  'code_changed',
  'service_mode_assigned',
  'admin_edit_profile',
  'admin_note_added',
  'admin_created',
  'admin_deactivated',
  'phone_changed',
  'edits_acknowledged',
  'work_type_assigned',
  'job_posted',
  'job_closed',
  'job_response',
  'admin_document_uploaded'
));
