-- ============================================
-- Removed the "Needs caregiver assistance with tube feeding" checkbox from
-- the job posting form — the feeding_type dropdown (tube_feeding /
-- oral_and_tube) is enough on its own, no extra field needed.
-- ============================================

ALTER TABLE care_receivers DROP COLUMN IF EXISTS tube_feeding_needs_assistance;
