-- ============================================
-- Remove father_name, father_phone, current_address, and notes entirely —
-- no longer collected anywhere in the product (caregiver Advanced Details
-- form, self-edit, or admin edit/view). Irreversible: any previously
-- collected values are dropped.
-- ============================================
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS father_name;
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS father_phone;
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS current_address;
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS notes;
