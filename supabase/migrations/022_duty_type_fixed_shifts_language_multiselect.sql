-- ============================================
-- Duty Type is now exactly 3 fixed shifts (24Hrs Live-In, 12Hrs Day Shift
-- 8am-8pm, 12Hrs Night Shift 8pm-8am) — 'other' is dropped, and admins no
-- longer enter start/end time separately (the shift's timing is implied by
-- which duty type is picked; jobs.start_time/end_time are now derived and
-- stored by the backend, not admin-entered).
--
-- Language Preference becomes a multi-select — jobs.language (single
-- VARCHAR) is replaced with jobs.languages (JSONB array), same pattern as
-- care_receivers.medical_assistance.
--
-- No data migration needed: 0 rows exist in `jobs` at the time of this
-- migration (confirmed via count before running).
-- ============================================

ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_duty_type_check;
ALTER TABLE jobs ADD CONSTRAINT jobs_duty_type_check
  CHECK (duty_type IN ('day_duty', 'night_duty', 'live_in'));

ALTER TABLE jobs DROP COLUMN language;
ALTER TABLE jobs ADD COLUMN languages JSONB NOT NULL DEFAULT '[]';
