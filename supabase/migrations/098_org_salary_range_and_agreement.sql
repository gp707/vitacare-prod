-- Organisations (hospital / rehab / clinic / agency):
--   1. may give a SALARY RANGE on a requirement (min, max, per day|month) — optional, editable at any time;
--   2. after accepting a caregiver, record the FINAL (agreed) salary and start date, like a patient does
--      (migrations 091/092/097 for jobs). Every entry/change is appended to a log for the activity log.
--
-- Additive and nullable everywhere: safe to apply before the backend that uses it is deployed.

ALTER TABLE organisation_requirements
  ADD COLUMN IF NOT EXISTS salary_min  INTEGER,
  ADD COLUMN IF NOT EXISTS salary_max  INTEGER,
  ADD COLUMN IF NOT EXISTS salary_unit VARCHAR(10);

-- All three set together or none; min > 0, max >= min, unit daily|monthly.
ALTER TABLE organisation_requirements DROP CONSTRAINT IF EXISTS organisation_requirements_salary_range_check;
ALTER TABLE organisation_requirements ADD CONSTRAINT organisation_requirements_salary_range_check CHECK (
  (salary_min IS NULL AND salary_max IS NULL AND salary_unit IS NULL)
  OR (salary_min IS NOT NULL AND salary_max IS NOT NULL AND salary_unit IN ('daily', 'monthly')
      AND salary_min > 0 AND salary_max >= salary_min)
);

ALTER TABLE organisation_requirement_applications
  ADD COLUMN IF NOT EXISTS agreed_salary      INTEGER CHECK (agreed_salary IS NULL OR agreed_salary > 0),
  ADD COLUMN IF NOT EXISTS agreed_salary_unit VARCHAR(10) CHECK (agreed_salary_unit IS NULL OR agreed_salary_unit IN ('daily', 'monthly')),
  ADD COLUMN IF NOT EXISTS agreed_start_date  DATE,
  ADD COLUMN IF NOT EXISTS agreed_at          TIMESTAMPTZ;

-- One row per entry/change of the agreed salary and start date (rows go with the application).
CREATE TABLE IF NOT EXISTS organisation_application_agreement_log (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES organisation_requirement_applications(id) ON DELETE CASCADE,
  salary         INTEGER NOT NULL CHECK (salary > 0),
  salary_unit    VARCHAR(10) NOT NULL CHECK (salary_unit IN ('daily', 'monthly')),
  start_date     DATE NOT NULL,
  set_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_org_agreement_log_application
  ON organisation_application_agreement_log (application_id, set_at);
