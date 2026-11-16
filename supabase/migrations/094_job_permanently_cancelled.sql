-- "Permanently cancel" (patient): the job is never put in front of caregivers again, but the
-- caregiver already accepted on it is NOT touched — they stay accepted, with their agreed
-- salary, leave days and pauses.
--
-- jobs.status stays 'closed' (an accepted caregiver already closed it). This flag is what makes
-- it permanent: nothing automatic reopens the job any more (rejecting the caregiver later, or
-- the caregiver closing duty), and the patient is not offered "Make it live again".
-- Deliberately separate from cancelled_at (the reversible "Cancel the Job", which rejects
-- candidates and hides the applicant list).
--
-- Additive and nullable: safe to apply before the backend that uses it is deployed.

ALTER TABLE jobs ADD COLUMN IF NOT EXISTS permanently_cancelled_at TIMESTAMPTZ;
