-- ============================================
-- CAREGIVER PROFILES TABLE
-- ============================================
CREATE TABLE caregiver_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  selfie_photo_url TEXT,
  gender VARCHAR(30) NOT NULL CHECK (gender IN ('male', 'female', 'other')),
  age INTEGER NOT NULL CHECK (age >= 18 AND age <= 65),
  highest_qualification VARCHAR(100),
  qualification_document_url TEXT,
  aadhaar_document_url TEXT,
  religion VARCHAR(20) CHECK (religion IN ('hindu', 'muslim', 'christian', 'others')),
  father_name VARCHAR(100),
  father_phone VARCHAR(20),
  mother_name VARCHAR(100),
  mother_phone VARCHAR(20),
  current_address TEXT CHECK (char_length(current_address) <= 500),
  other_document_urls JSONB DEFAULT '[]',
  salary DECIMAL(10, 2) CHECK (salary >= 0),  -- Admin-assigned, visible to caregiver
  available_from DATE,
  preferred_city VARCHAR(30) CHECK (preferred_city IN ('bangalore', 'mumbai', 'hyderabad', 'chennai', 'pune', 'delhi', 'gurgaon')),
  notes TEXT CHECK (char_length(notes) <= 500),
  terms_accepted BOOLEAN DEFAULT false,
  verification_status VARCHAR(30) DEFAULT 'pending_call'
    CHECK (verification_status IN (
      'pending_call',
      'call_verified',
      'pending_verification',
      'in_process',
      'available',
      'unavailable',
      'assigned',
      'rejected'
    )),
  rejection_message TEXT,
  call_verified_at TIMESTAMPTZ,
  call_verified_by UUID REFERENCES users(id),  -- App validates this is admin/super_admin
  advanced_details_completed BOOLEAN DEFAULT false,
  has_pending_edits BOOLEAN DEFAULT false,
  submitted_at TIMESTAMPTZ,
  verified_at TIMESTAMPTZ,
  verified_by UUID REFERENCES users(id),      -- App validates this is admin/super_admin
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_caregiver_profiles_status ON caregiver_profiles(verification_status);
CREATE INDEX idx_caregiver_profiles_created_at ON caregiver_profiles(created_at);
