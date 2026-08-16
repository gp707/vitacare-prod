-- ============================================
-- Communication field simplified to 3 options (relabeled, 'other_non_verbal'
-- dropped entirely). Enum keys/values for the remaining 3 are unchanged
-- (verbal, difficulty_communicating, sign_language) — only their display
-- labels change in the UI:
--   verbal                   -> "Can Speak/Communicate"
--   difficulty_communicating -> "Can NOT Speak"
--   sign_language             -> "Communicate via Sign Languages"
--
-- No existing care_receivers row uses 'other_non_verbal' (confirmed via
-- SELECT before writing this migration), so no data migration needed.
-- ============================================

ALTER TABLE care_receivers DROP CONSTRAINT IF EXISTS care_receivers_communication_check;
ALTER TABLE care_receivers ADD CONSTRAINT care_receivers_communication_check
  CHECK (communication IN ('verbal', 'difficulty_communicating', 'sign_language'));
