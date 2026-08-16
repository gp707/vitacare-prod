-- ============================================
-- Admin-assigned work types, service modes, and salary are removed
-- entirely (no longer part of the product), along with the two rate
-- fields on admin_notes. All four are confirmed empty/unused in the live
-- DB as of this migration (0 rows in caregiver_work_types/
-- caregiver_service_modes, 0 non-null salary/rate values), so no data
-- migration is needed.
-- ============================================

DROP TABLE IF EXISTS caregiver_work_types;
DROP TABLE IF EXISTS caregiver_service_modes;

ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS salary;

ALTER TABLE admin_notes DROP COLUMN IF EXISTS rate_24hrs_live_in;
ALTER TABLE admin_notes DROP COLUMN IF EXISTS rate_12hrs_pg;

-- Drops work_type_assigned/service_mode_assigned (audit actions for the
-- removed assignment endpoints; confirmed 0 existing rows use either).
-- Deliberately does NOT touch 'call_verified'/'advanced_details_submitted'
-- here even though the AuditAction enum dropped them in migration 019's
-- session — 1 real historical row still has action='call_verified', and
-- audit_logs is immutable/append-only, so that pre-existing constraint
-- drift is left alone rather than force-validating a NOT VALID constraint
-- change against real history.
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'call_verified', 'advanced_details_submitted',
    'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'admin_document_uploaded', 'admin_role_changed', 'admin_activated', 'job_reminder_sent'
  ));
