-- Rate Card Guidance: a single admin-editable salary-guideline grid shown to
-- caregivers (NurseJobs) and individuals/family (NurseNow) -- deliberately
-- NOT shown to Organisation (hospital/rehab/clinic) accounts, since these
-- guidelines are for individual hiring, not institutional bulk hiring.
-- Singleton row (id fixed to 1) -- there's only ever one rate card, unlike
-- app_min_versions/otp_auth_settings which have one row per platform/app.
CREATE TABLE rate_card (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  title TEXT NOT NULL,
  column_labels TEXT[] NOT NULL,
  row_labels TEXT[] NOT NULL,
  cells JSONB NOT NULL,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO rate_card (id, title, column_labels, row_labels, cells) VALUES (
  1,
  'Salary Guidelines (12 hrs/24 hrs duty)',
  ARRAY['Companion care', 'Bedside Care', 'Critical Care'],
  ARRAY['Caregivers', 'Nursing students/Nursing with backlogs', 'Nurses (Nursing completed/Registered/Unregistered)'],
  '[
    ["26000 pm/867 per day", "28000 pm/933 per day", "Caregivers are not suggested"],
    ["28000 pm/933 per day", "30000 pm/1000 per day", "32000 pm/1067 per day"],
    ["30000 pm/1000 per day", "32000 pm/1067 per day", "35000-42000 pm (depending on years of experience)"]
  ]'::jsonb
);

ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'job_application_decided', 'admin_document_uploaded', 'admin_role_changed',
    'admin_activated', 'job_reminder_sent', 'job_updated', 'job_completed',
    'app_version_updated', 'org_requirement_posted', 'org_requirement_updated',
    'org_requirement_rejected', 'org_requirement_application_decided',
    'otp_setting_updated', 'job_reapplied', 'rate_card_updated'
  ));
