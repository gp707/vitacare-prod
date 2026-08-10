-- ============================================
-- CAREGIVER WORK TYPES TABLE (admin-assigned)
-- ============================================
CREATE TABLE caregiver_work_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  work_type VARCHAR(30) NOT NULL CHECK (work_type IN ('companion_care', 'bedside_care', 'critical_care')),
  assigned_by UUID NOT NULL REFERENCES users(id),
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(profile_id, work_type)
);

CREATE INDEX idx_caregiver_work_types_profile ON caregiver_work_types(profile_id);
