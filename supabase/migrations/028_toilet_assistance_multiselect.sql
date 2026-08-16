-- Toilet Assistance becomes multi-select (admin can select multiple options
-- that apply, matching the vital_monitoring_types/medical_assistance
-- pattern — no DB-level CHECK on array elements, validated at the DTO
-- layer only). Also: 'none' is renamed to 'others', and a new 'independent'
-- option is added.
--
-- 1 existing real row has toilet_assistance = 'uses_bed_pan' (not affected
-- by the none->others rename) — safe to wrap as a single-element array in
-- the same statement that does the rename.

ALTER TABLE care_receivers DROP CONSTRAINT IF EXISTS care_receivers_toilet_assistance_check;

ALTER TABLE care_receivers
  ALTER COLUMN toilet_assistance TYPE JSONB
  USING jsonb_build_array(CASE WHEN toilet_assistance = 'none' THEN 'others' ELSE toilet_assistance END);

ALTER TABLE care_receivers ALTER COLUMN toilet_assistance SET DEFAULT '[]';
