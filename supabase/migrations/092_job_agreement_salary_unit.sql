-- The patient/family picks whether the agreed salary is per day or per month (it used to
-- always follow the job's frequency_of_care). Stored next to agreed_salary (migration 091).
--
-- Additive and nullable: safe to apply before the backend that uses it is deployed. Rows
-- without it (none exist yet) fall back to the job's own frequency_of_care in the API/apps.

ALTER TABLE job_applications
  ADD COLUMN IF NOT EXISTS agreed_salary_unit VARCHAR(10)
    CHECK (agreed_salary_unit IS NULL OR agreed_salary_unit IN ('daily', 'monthly'));
