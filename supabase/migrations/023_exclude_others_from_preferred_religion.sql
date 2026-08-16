-- ============================================
-- "Others" is excluded from a job's preferred_religion — it remains a
-- valid value for a caregiver's own religion at registration, but is not
-- offered as a job's stated caregiver-religion preference. Mirrors how
-- preferred_gender already excludes 'other' at the DB level.
-- ============================================

ALTER TABLE jobs DROP CONSTRAINT IF EXISTS jobs_preferred_religion_check;
ALTER TABLE jobs ADD CONSTRAINT jobs_preferred_religion_check
  CHECK (preferred_religion IN ('hindu', 'muslim', 'christian'));
