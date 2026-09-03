-- Admin-editable content for NurseJobs (caregiver-app)'s Messages bell —
-- the caregiver-side counterpart to individual_messages (migration 061),
-- but a distinct table with its own event taxonomy: individual_messages
-- describes events on an Individual's own posted requirement (e.g. "a
-- caregiver applied to MY job"); this table describes events on a
-- caregiver's own application lifecycle (e.g. "I applied to a job", "I
-- was accepted") — the opposite direction, so it gets its own table
-- rather than overloading individual_messages' event enum. See
-- CaregiverMessageEvent in packages/shared-constants/src/enums.ts:
--   'welcome'      — caregiver has never applied to any job yet
--   'job_applied'  — a currently-active job has my_application.status == applied
--   'job_accepted' — an assigned job has my_application.status == accepted
--   'job_rejected' — a currently-active job has my_application.status == rejected
--   'job_closed'   — an assigned job has my_application.status == completed
-- event/icon are validated at the DTO layer (@IsIn), not a DB CHECK, same
-- convention as individual_messages/Type of Nurse. Message text may
-- contain the literal token "{job_id}", substituted client-side with the
-- relevant job's display id (see resolveCaregiverMessages() in
-- apps/caregiver-app/lib/features/jobs/data/caregiver_messages_logic.dart).
-- No seed rows — this is genuinely new content, nothing to preserve
-- behavior-identically for (unlike individual_messages, which replaced
-- hardcoded tips).
CREATE TABLE caregiver_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event VARCHAR(30) NOT NULL,
  icon VARCHAR(30) NOT NULL,
  message TEXT NOT NULL,
  display_order INT NOT NULL DEFAULT 0,
  enabled BOOLEAN NOT NULL DEFAULT true,
  created_by UUID REFERENCES users(id),
  updated_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Widen the audit_logs action CHECK constraint for the 3 new action
-- values, preserving every existing value (verified against the live DB's
-- actual current constraint, not just migration 061's file, to make sure
-- nothing added directly against the live DB since then is dropped here).
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
    'caregiver_message_created', 'caregiver_message_updated', 'caregiver_message_deleted'
  ));
