-- ============================================
-- Force-upgrade support becomes per-app: app_min_versions previously held
-- one row per platform, checked only by the caregiver app (NurseJobs).
-- NurseNow (nursenow-app) needs its own independent min_version/store_url/
-- update_message per platform too, so an admin can force-upgrade either
-- app without affecting the other. Existing rows are NurseJobs' own —
-- backfilled to app = 'nursejobs' via the column default so the caregiver
-- app's current behavior is unchanged, then two new rows seed NurseNow at
-- the same "don't gate anyone until an admin deliberately raises the bar"
-- baseline the original migration (031) used.
-- ============================================

ALTER TABLE app_min_versions ADD COLUMN app VARCHAR(10) NOT NULL DEFAULT 'nursejobs';
ALTER TABLE app_min_versions ALTER COLUMN app DROP DEFAULT;
ALTER TABLE app_min_versions ADD CONSTRAINT app_min_versions_app_check
  CHECK (app IN ('nursejobs', 'nursenow'));

ALTER TABLE app_min_versions DROP CONSTRAINT app_min_versions_pkey;
ALTER TABLE app_min_versions ADD CONSTRAINT app_min_versions_pkey PRIMARY KEY (app, platform);

INSERT INTO app_min_versions (app, platform, min_version) VALUES
  ('nursenow', 'android', '1.0.0'),
  ('nursenow', 'ios', '1.0.0');

-- ============================================
-- Maintenance / read-only mode — admin can take either app down entirely
-- with a custom message (e.g. "App is in maintenance mode, it will be
-- available after 10am IST"). Checked by both apps on every cold launch,
-- same launch-time/fail-open/pre-login contract as the version check
-- (see AppVersionRepository.checkForUpdate) — a non-dismissible full-screen
-- notice blocks all use of the app until an admin turns it back off.
-- One row per app, seeded disabled so nobody is affected until an admin
-- deliberately switches it on.
-- ============================================

CREATE TABLE app_maintenance (
  app VARCHAR(10) PRIMARY KEY CHECK (app IN ('nursejobs', 'nursenow')),
  enabled BOOLEAN NOT NULL DEFAULT false,
  message TEXT,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO app_maintenance (app, enabled, message) VALUES
  ('nursejobs', false, NULL),
  ('nursenow', false, NULL);

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
    'audit_log_retention_updated', 'audit_logs_purged', 'app_maintenance_updated'
  ));
