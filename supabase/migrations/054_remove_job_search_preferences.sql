-- Job search preferences removed from the product entirely (NurseJobs only)
-- — a caregiver can no longer set preferred_duty_types or a minimum salary,
-- and GET /caregiver/jobs no longer filters by any of these (or by
-- preferred_cities). caregiver_preferred_cities itself is NOT dropped here
-- — admin-web's Caregivers list still filters/displays it, and admins can
-- still set it via PUT /admin/caregivers/:id; only the caregiver's own
-- ability to set it (registration + self-edit) and the job-matching use of
-- it were removed, in application code, not the schema.
DROP TABLE caregiver_preferred_duty_types;

ALTER TABLE caregiver_profiles
  DROP COLUMN min_salary_per_day,
  DROP COLUMN min_salary_per_month;
