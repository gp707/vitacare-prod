-- Batch of NurseNow Organisation enhancements:
--   1. Adds 'agency' as a 4th organisation_type (hospital/rehab/clinic/agency).
--   2. Makes organisation_profiles.area optional at registration (was
--      required at both the DB and DTO layers).
--   3. organisation_requirements gains type_of_nurse_other (free text when
--      type_of_nurse = 'others', mirroring care_receivers.medical_condition_other/
--      toilet_assistance_other), number_of_vacancies (org-set at creation,
--      1-49, defaults to 1), preferred_gender (org-set at creation,
--      male/female/null — mirrors jobs.preferred_gender exactly, including
--      excluding 'other' at the DB level), and cancelled_at (mirrors
--      jobs.cancelled_at — migration 048 — backing a new org self-cancel
--      endpoint, JobsRepository.cancel's exact counterpart).

ALTER TABLE organisation_profiles DROP CONSTRAINT IF EXISTS organisation_profiles_organisation_type_check;
ALTER TABLE organisation_profiles ADD CONSTRAINT organisation_profiles_organisation_type_check
  CHECK (organisation_type IN ('hospital', 'rehab', 'clinic', 'agency'));

ALTER TABLE organisation_profiles ALTER COLUMN area DROP NOT NULL;

ALTER TABLE organisation_requirements ADD COLUMN type_of_nurse_other TEXT;
ALTER TABLE organisation_requirements ADD COLUMN number_of_vacancies INTEGER NOT NULL DEFAULT 1
  CHECK (number_of_vacancies > 0 AND number_of_vacancies < 50);
ALTER TABLE organisation_requirements ADD COLUMN preferred_gender VARCHAR(10)
  CHECK (preferred_gender IN ('male', 'female'));
ALTER TABLE organisation_requirements ADD COLUMN cancelled_at TIMESTAMPTZ;

-- Widen the audit_logs action CHECK constraint — org self-edit/self-cancel
-- reuse the existing org_requirement_updated/job_closed-style actions
-- (see OrganisationRequirementsService), so no new action values are
-- actually needed this time; this ALTER is a no-op left out deliberately.
