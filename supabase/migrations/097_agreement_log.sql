-- Every time the patient/family enters or changes the agreed salary and start date for a
-- caregiver, one row is appended here, so the caregiver's activity log can show the whole
-- history (the job_applications row itself only keeps the latest values).
--
-- Rows go when the application row goes (ON DELETE CASCADE). They are never updated or deleted
-- otherwise: a re-acceptance clears the current agreement on the application but its history
-- stays in the log.
--
-- Additive: safe to apply before the backend that uses it is deployed. The backfill gives every
-- agreement that exists today one starting entry.

CREATE TABLE IF NOT EXISTS job_application_agreement_log (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  application_id UUID NOT NULL REFERENCES job_applications(id) ON DELETE CASCADE,
  salary         INTEGER NOT NULL CHECK (salary > 0),
  salary_unit    VARCHAR(10) NOT NULL CHECK (salary_unit IN ('daily', 'monthly')),
  start_date     DATE NOT NULL,
  set_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agreement_log_application ON job_application_agreement_log (application_id, set_at);

-- One starting entry for each agreement that already exists (only when the log is still empty).
INSERT INTO job_application_agreement_log (application_id, salary, salary_unit, start_date, set_at)
SELECT ja.id, ja.agreed_salary, COALESCE(ja.agreed_salary_unit, 'monthly'), ja.agreed_start_date, COALESCE(ja.agreed_at, ja.updated_at, NOW())
FROM job_applications ja
WHERE ja.agreed_salary IS NOT NULL AND ja.agreed_start_date IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM job_application_agreement_log l WHERE l.application_id = ja.id);
