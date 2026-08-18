-- Caregiver job search preferences: caregivers can now set which shift
-- types and minimum salary they're willing to work, on top of the existing
-- preferred_cities. All optional, editable anytime via the self-edit
-- endpoint like every other preference field — no admin approval and no
-- verification_status change. GET /caregiver/jobs filters dynamically off
-- whatever is currently stored; unset means no filter on that dimension.
--
-- Duty type preference uses the same many-to-many junction-table pattern
-- as caregiver_preferred_cities (see 014) since it's multi-select.
CREATE TABLE caregiver_preferred_duty_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  duty_type VARCHAR(20) NOT NULL CHECK (duty_type IN ('live_in', 'day_duty', 'night_duty')),
  UNIQUE(profile_id, duty_type)
);

CREATE INDEX idx_caregiver_preferred_duty_types_profile ON caregiver_preferred_duty_types(profile_id);

-- Two separate thresholds rather than one number + unit, since jobs
-- themselves carry two incompatible salary scales (₹/day vs ₹/month
-- depending on frequency_of_care) — a daily job is only ever compared
-- against min_salary_per_day, a monthly job only against
-- min_salary_per_month. Either (or both) can be left NULL.
ALTER TABLE caregiver_profiles ADD COLUMN min_salary_per_day INTEGER CHECK (min_salary_per_day > 0);
ALTER TABLE caregiver_profiles ADD COLUMN min_salary_per_month INTEGER CHECK (min_salary_per_month > 0);
