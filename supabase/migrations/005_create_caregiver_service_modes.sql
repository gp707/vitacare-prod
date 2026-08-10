-- ============================================
-- CAREGIVER SERVICE MODES TABLE
-- ============================================
CREATE TABLE caregiver_service_modes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  service_mode VARCHAR(20) NOT NULL CHECK (service_mode IN ('24hrs_live_in', '12hrs_pg')),
  UNIQUE(profile_id, service_mode)
);

CREATE INDEX idx_caregiver_service_modes_profile ON caregiver_service_modes(profile_id);
