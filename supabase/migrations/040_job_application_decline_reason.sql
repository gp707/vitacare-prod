-- A caregiver applicant's decline reason — mandatory in nursenow-app's
-- one-at-a-time applicant review flow when a patient/family rejects a
-- candidate (enforced in IndividualService.decideMyApplication, not here —
-- admin's own reject flow leaves this optional/unused). NULL for every
-- other status transition (accept, or an admin reject without a reason).
ALTER TABLE job_applications ADD COLUMN decline_reason TEXT;
