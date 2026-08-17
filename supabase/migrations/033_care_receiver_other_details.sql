-- ============================================
-- Free-text detail attached to the "Others" option of two multi-selects.
-- Selecting Others (`others` for toilet_assistance, `other` for
-- medical_conditions) reveals a small text field in the admin-web form so
-- the admin can describe what "other" actually means, alongside whichever
-- other options are also selected (both fields stay multi-select).
-- ============================================

ALTER TABLE care_receivers
  ADD COLUMN toilet_assistance_other TEXT,
  ADD COLUMN medical_condition_other TEXT;
