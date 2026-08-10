-- ============================================
-- Remove mother's name/phone entirely — no longer collected anywhere in
-- the product (caregiver Advanced Details form, admin edit, or admin
-- view). Irreversible: any previously-collected values are dropped.
-- ============================================
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS mother_name;
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS mother_phone;
