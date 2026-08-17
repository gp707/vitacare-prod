-- ============================================
-- Force-upgrade support: admin-controlled minimum supported app version,
-- per platform. Checked by the caregiver app on launch (before login) via
-- the public GET /app-versions/check endpoint — versions below
-- min_version are blocked with an "Update Required" screen until the
-- caregiver updates.
-- ============================================

CREATE TABLE app_min_versions (
  platform VARCHAR(10) PRIMARY KEY CHECK (platform IN ('android', 'ios')),
  min_version VARCHAR(20) NOT NULL,
  store_url TEXT,
  update_message TEXT,
  updated_by UUID REFERENCES users(id),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seeded at the app's current released version so nobody is gated until an
-- admin deliberately raises the bar after a new release.
INSERT INTO app_min_versions (platform, min_version) VALUES
  ('android', '1.0.0'),
  ('ios', '1.0.0');

ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'call_verified', 'advanced_details_submitted',
    'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'job_application_decided',
    'admin_document_uploaded', 'admin_role_changed', 'admin_activated', 'job_reminder_sent',
    'job_updated', 'app_version_updated'
  ));
