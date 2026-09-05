-- A caregiver's own reason for closing an accepted job/requirement (the
-- "Mark Complete"/"Close" action, POST .../complete) — a fixed dropdown,
-- not free text like decline_reason (that one is the OTHER side rejecting
-- a candidate; this is the caregiver ending their own engagement).
-- Defaults to 'no_reason' so a caregiver who submits without picking
-- anything else still always has a real, explicit value stored — never
-- NULL for a newly-completed application. Visible to both the caregiver
-- themselves (their own MyJobs timeline) and the job/requirement poster
-- (admin/individual/organisation), since it's just another column on the
-- same job_applications/organisation_requirement_applications rows those
-- API responses already select in full.
ALTER TABLE job_applications ADD COLUMN close_reason VARCHAR(30) DEFAULT 'no_reason' CHECK (
  close_reason IN (
    'duty_complete',
    'no_reason',
    'did_not_like_work',
    'temporarily_not_available',
    'family_problems',
    'need_to_go_hometown'
  )
);

ALTER TABLE organisation_requirement_applications ADD COLUMN close_reason VARCHAR(30) DEFAULT 'no_reason' CHECK (
  close_reason IN (
    'duty_complete',
    'no_reason',
    'did_not_like_work',
    'temporarily_not_available',
    'family_problems',
    'need_to_go_hometown'
  )
);
