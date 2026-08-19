-- Splits the single shared jobs.job_number display into two independent,
-- poster-role-specific sequences, each starting at 500. job_number itself
-- is left untouched (still populated, still used internally for
-- audit-log job resolution) — it's simply no longer the user-facing
-- display id. Exactly one of the two new columns is populated per row,
-- set at INSERT time based on who posted the job:
--   admin_job_number   -- admin-posted jobs; displayed as "ADMIN-JOB-<n>"
--   patient_job_number -- NurseNow individual-posted jobs; "PAT-JOB-<n>"
CREATE SEQUENCE jobs_admin_job_number_seq START WITH 500;
ALTER TABLE jobs ADD COLUMN admin_job_number INTEGER UNIQUE;
ALTER SEQUENCE jobs_admin_job_number_seq OWNED BY jobs.admin_job_number;

CREATE SEQUENCE jobs_patient_job_number_seq START WITH 500;
ALTER TABLE jobs ADD COLUMN patient_job_number INTEGER UNIQUE;
ALTER SEQUENCE jobs_patient_job_number_seq OWNED BY jobs.patient_job_number;

-- organisation_requirements.requirement_number is already organisation-only
-- (no shared-poster ambiguity like jobs has) — no new column needed, just
-- rebase its existing sequence to start at 500 so it can be displayed as
-- "ORG-JOB-<n>" going forward, replacing the old "Requirement #<n>" label.
ALTER SEQUENCE organisation_requirements_requirement_number_seq RESTART WITH 500;
