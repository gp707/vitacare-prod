-- Admin-editable content for NurseNow Individual's "Messages" tab —
-- replaces the previously hardcoded tips in
-- apps/nursenow-app/lib/features/individual/data/requirement_messages.dart.
-- Unlike rate_card/scope_of_work/duty_requirements (singleton rows), this
-- is a real multi-row table: admin can create/edit/delete any number of
-- messages, each tied to one of 3 delivery events (see MessageEvent in
-- packages/shared-constants/src/enums.ts):
--   'welcome'                — account has never posted a requirement
--   'requirement_live'       — account has a currently pending_review/active requirement
--   'requirement_care_tier'  — same as above, and that requirement has a care_receiver;
--                               message text may contain the literal token
--                               "{tier}", substituted client-side with the
--                               derived care tier's display name
-- event/icon are validated at the DTO layer (@IsIn), not a DB CHECK, so
-- either list can grow without a migration — same convention as
-- Type of Nurse. display_order is a single global ordering (not grouped
-- per event) so admin fully controls how messages from different events
-- interleave when shown together.
CREATE TABLE individual_messages (
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

-- Seeded with the exact 6 messages that were previously hardcoded, so
-- behavior is unchanged the moment this ships — admin can then edit/
-- reorder/disable/delete/add from here.
INSERT INTO individual_messages (event, icon, message, display_order) VALUES
  (
    'requirement_live',
    'edit_note',
    'You can edit this job and change salary. Typically it takes 3 to 5 days for caregivers to reach out. If urgent, do not hesitate to click on the red button at the top of the app for help.',
    10
  ),
  (
    'requirement_care_tier',
    'favorite',
    'Based on the patient''s condition we see you need {tier}. You may look at the standard Rate Card for this care level. You can also tap Scope of Work on the job listing to see exactly what it covers.',
    20
  ),
  (
    'requirement_live',
    'rule',
    'You can post one requirement at a time — once the existing requirement is closed, fulfilled, or cancelled, you can post another. Tip: you may cancel a requirement at any time.',
    30
  ),
  (
    'requirement_live',
    'travel_explore',
    'If you are not getting applicants, consider widening your scope: move to a monthly or long-term requirement, stay open to candidates of any religion, or set Preferred Caregiver Gender and Language Preference to "No Preference" — caregivers are trained to handle any gender, so this can significantly widen your pool of candidates.',
    40
  ),
  (
    'welcome',
    'waving_hand',
    'Welcome to NurseNow! Use Profile to manage your phone number and login PIN, Messages (this tab) for tips and updates about your posted job, and Jobs Posted to post a requirement and review the caregivers who apply.',
    10
  ),
  (
    'welcome',
    'rocket_launch',
    'Ready to get started? Head to the Jobs Posted tab and tap "Post a Requirement" to describe the care you need — most caregivers typically reach out within 3 to 5 days once it goes live.',
    20
  );

-- Widen the audit_logs action CHECK constraint for the 3 new action
-- values, preserving every existing value (including duty_requirements_
-- updated/job_settings_updated/admin_password_changed, which were added
-- directly against the live DB rather than via a committed migration —
-- verified against the current packages/shared-constants/src/enums.ts
-- AuditAction object so none of them are silently dropped here).
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
    'individual_message_created', 'individual_message_updated', 'individual_message_deleted'
  ));
