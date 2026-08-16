-- ============================================
-- Universal job id: job_number is a short sequential number shown
-- prominently ("Job #<n>") to both admin and caregivers, distinct from the
-- internal UUID `id`. SERIAL backfills existing rows automatically.
--
-- Salary: admin now specifies a single monthly amount per job, highlighted
-- on the caregiver's screen. Nullable at the DB level (1 real job already
-- exists from before this field existed, and its true salary is unknown —
-- faking a number would be worse than leaving it null); the API layer
-- (CreateJobDto/UpdateJobDto) requires it on every create/edit going
-- forward, so it can only be null for that one pre-existing row until an
-- admin edits and saves it.
--
-- Urgency window: `posted_at` is the effective "went live" timestamp,
-- separate from the immutable `created_at`. It starts equal to created_at
-- and is bumped to NOW() only when a closed job is edited-and-reposted
-- (not on a plain edit of an already-active job) — the "apply within 3
-- days" caregiver-facing countdown is always created from posted_at, not
-- created_at, so a repost genuinely restarts the urgency window to match
-- the repost's re-broadcast push.
-- ============================================

ALTER TABLE jobs ADD COLUMN job_number SERIAL UNIQUE;
ALTER TABLE jobs ADD COLUMN salary_monthly INTEGER CHECK (salary_monthly > 0);
ALTER TABLE jobs ADD COLUMN posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE jobs SET posted_at = created_at WHERE posted_at IS DISTINCT FROM created_at;
