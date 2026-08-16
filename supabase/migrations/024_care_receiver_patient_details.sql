-- ============================================
-- "Care Receiver" section on the job-posting form is now "About Patient" in
-- the UI (label-only change, no rename of the underlying table/columns —
-- still care_receivers, kept distinct from a future real "Patient" entity
-- per the existing 1:1-with-job design).
--
-- New fields on care_receivers: age, gender, weight_kg (basic identifying
-- details to help a caregiver decide), toilet_assistance (single-select),
-- requires_vital_monitoring + vital_monitoring_types (Yes/No + conditional
-- multi-select, same pattern as has_medical_condition/medical_conditions).
--
-- 0 rows exist in care_receivers at the time of this migration (the one
-- test row was deleted by hand first, confirmed with the user), so all new
-- columns can be added NOT NULL directly with no backfill.
-- ============================================

ALTER TABLE care_receivers ADD COLUMN age INTEGER NOT NULL CHECK (age BETWEEN 1 AND 120);
ALTER TABLE care_receivers ADD COLUMN gender VARCHAR(10) NOT NULL CHECK (gender IN ('male', 'female', 'other'));
ALTER TABLE care_receivers ADD COLUMN weight_kg INTEGER NOT NULL CHECK (weight_kg BETWEEN 1 AND 300);

ALTER TABLE care_receivers ADD COLUMN toilet_assistance VARCHAR(30) NOT NULL CHECK (toilet_assistance IN (
  'uses_diapers', 'uses_bed_pan', 'uses_catheter', 'complete_toileting_assistance', 'none'
));

ALTER TABLE care_receivers ADD COLUMN requires_vital_monitoring BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE care_receivers ADD COLUMN vital_monitoring_types JSONB NOT NULL DEFAULT '[]';
