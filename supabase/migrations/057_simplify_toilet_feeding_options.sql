-- Toilet Assistance and Feeding/Medicine Assistance are simplified down to
-- 4 and 3 options respectively:
--   ToiletAssistance: independent, diapers_bedside_support (replaces
--     uses_diapers + uses_bed_pan), uses_catheter, others
--     (complete_toileting_assistance is dropped entirely)
--   FeedingType: oral_feeding (replaces oral_independent +
--     oral_needs_assistance), tube_feeding, others (replaces oral_and_tube
--     — now framed as "Others (Cannula etc.)", a different meaning, not a
--     rename)
--
-- toilet_assistance has no DB-level CHECK (JSONB array, validated at the
-- DTO layer only — see migration 028), so nothing to change there.
-- feeding_type is a single VARCHAR CHECK column (migration 021) and does
-- need updating. No production data existed on any of the removed values
-- at the time of this migration (verified directly) — every real
-- feeding_type row was already 'oral_independent', which folds losslessly
-- into the new 'oral_feeding'.

ALTER TABLE care_receivers DROP CONSTRAINT IF EXISTS care_receivers_feeding_type_check;

UPDATE care_receivers SET feeding_type = 'oral_feeding'
  WHERE feeding_type IN ('oral_independent', 'oral_needs_assistance');
UPDATE care_receivers SET feeding_type = 'others' WHERE feeding_type = 'oral_and_tube';

ALTER TABLE care_receivers ADD CONSTRAINT care_receivers_feeding_type_check
  CHECK (feeding_type IN ('oral_feeding', 'tube_feeding', 'others'));
