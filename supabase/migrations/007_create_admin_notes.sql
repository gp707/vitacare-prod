-- ============================================
-- ADMIN NOTES TABLE
-- ============================================
CREATE TABLE admin_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES users(id),
  internal_notes TEXT,
  rate_24hrs_live_in DECIMAL(10, 2) CHECK (rate_24hrs_live_in >= 0),
  rate_12hrs_pg DECIMAL(10, 2) CHECK (rate_12hrs_pg >= 0),
  availability_remarks TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(profile_id)
);
