-- Drops organisation_requirements.duration_type (added in migration 066) —
-- removed from the product entirely, organisation-flow-only (the separate
-- Individual-side jobs.care_duration field is untouched). Replaced by two
-- new org-owned, optional fields for the same posting form:
--   experience_required: 'fresher' | '1_2_years' | '3_5_years' |
--     '5_10_years' | '10_plus_years'
--   employment_type: 'full_time' | 'part_time' | 'temporary'
ALTER TABLE organisation_requirements DROP COLUMN duration_type;

ALTER TABLE organisation_requirements ADD COLUMN experience_required VARCHAR(20)
  CHECK (experience_required IN ('fresher', '1_2_years', '3_5_years', '5_10_years', '10_plus_years'));

ALTER TABLE organisation_requirements ADD COLUMN employment_type VARCHAR(20)
  CHECK (employment_type IN ('full_time', 'part_time', 'temporary'));
