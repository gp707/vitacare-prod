-- Scheduled push notifications:
--   1. Duty-start reminders for caregivers with an accepted job: "you start in
--      2 days" / "in 1 day" / "soon — do not forget" (under 12 hours).
--   2. A one-time "no applicants yet" nudge to a patient or organisation whose
--      requirement has been live for 3 days with nobody applying.
--
-- One timestamp per reminder so each is sent at most once per acceptance. The
-- sender claims a reminder with UPDATE ... WHERE duty_reminder_*_at IS NULL
-- before sending, so two API instances running the same schedule can never
-- both send it. They are cleared when the caregiver is (re-)accepted or the
-- job's start date changes, so a new date gets its own reminders.
--
-- Additive and nullable: safe to apply before the API that uses it is deployed.

ALTER TABLE job_applications
  ADD COLUMN IF NOT EXISTS duty_reminder_2d_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS duty_reminder_1d_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS duty_reminder_12h_at TIMESTAMPTZ;

-- The reminder sweep only ever looks at accepted applications.
CREATE INDEX IF NOT EXISTS idx_job_applications_accepted
  ON job_applications (job_id) WHERE status = 'accepted';

-- "No applicants after 3 days" nudge: stamped when sent so it goes out once.
-- Cleared whenever the posting is (re)activated (JobsRepository.activate /
-- OrganisationRequirementsRepository.activate), so a reposted requirement can
-- be nudged again after its own 3 days.
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS no_applicants_nudge_at TIMESTAMPTZ;
ALTER TABLE organisation_requirements ADD COLUMN IF NOT EXISTS no_applicants_nudge_at TIMESTAMPTZ;
