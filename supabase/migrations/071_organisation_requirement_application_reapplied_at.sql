-- organisation_requirement_applications was missing a reapplied_at column
-- entirely — job_applications has always had one (stamped when a fresh
-- 'applied' overwrites a previously 'rejected'/'completed' row), letting
-- both the caregiver and the job poster see that a re-apply cycle
-- happened even after accepted_at/rejected_at/completed_at get cleared by
-- the new apply. Organisation requirements never got the same column, so
-- a caregiver who was rejected (or closed the requirement themselves) and
-- then re-applied left no trace of it ever having happened. Mirrors
-- job_applications.reapplied_at exactly.
ALTER TABLE organisation_requirement_applications ADD COLUMN reapplied_at TIMESTAMPTZ;
