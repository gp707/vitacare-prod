-- ============================================
-- CAREGIVER PREFERRED CITIES TABLE
-- Caregiver can now select MULTIPLE preferred cities, not just one —
-- same many-to-many junction-table pattern as caregiver_languages,
-- caregiver_service_modes, caregiver_work_types (see 004/005/006).
-- ============================================
CREATE TABLE caregiver_preferred_cities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  city VARCHAR(30) NOT NULL CHECK (city IN (
    'bangalore', 'mumbai', 'hyderabad', 'chennai', 'pune', 'delhi', 'gurgaon'
  )),
  UNIQUE(profile_id, city)
);

CREATE INDEX idx_caregiver_preferred_cities_profile ON caregiver_preferred_cities(profile_id);
