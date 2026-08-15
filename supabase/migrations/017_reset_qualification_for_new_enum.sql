-- ============================================
-- Qualification enum was restructured (5 old values replaced by 6 new
-- tiers that don't map cleanly onto the old ones — e.g. the old values
-- didn't capture registration status or years of experience). Per
-- decision: reset existing values rather than guess a mapping, so admins
-- can re-select the correct new tier for each affected caregiver.
-- ============================================
UPDATE caregiver_profiles
SET highest_qualification = NULL
WHERE highest_qualification IN (
  'bsc_gnm_completed',
  'anm_completed',
  'bsc_gnm_anm_backlog',
  'bsc_gnm_anm_student',
  'non_nursing'
);
