-- ============================================
-- Backfill existing single preferred_city values into the new
-- caregiver_preferred_cities table, then drop the old scalar column.
-- ============================================
INSERT INTO caregiver_preferred_cities (profile_id, city)
SELECT id, preferred_city FROM caregiver_profiles WHERE preferred_city IS NOT NULL
ON CONFLICT (profile_id, city) DO NOTHING;

ALTER TABLE caregiver_profiles DROP COLUMN IF EXISTS preferred_city;
