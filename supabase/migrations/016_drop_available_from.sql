-- ============================================
-- Remove available_from entirely — no longer collected anywhere in the
-- product (caregiver Advanced Details form, self-edit, or admin edit/view).
-- Irreversible: any previously-collected values are dropped.
-- ============================================
ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS available_from;
