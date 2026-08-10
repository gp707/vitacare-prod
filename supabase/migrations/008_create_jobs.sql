-- ============================================
-- JOBS TABLE (admin-posted job listings)
-- ============================================
CREATE TABLE jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  work_type VARCHAR(30) NOT NULL CHECK (work_type IN ('companion_care', 'bedside_care', 'critical_care')),
  city VARCHAR(30) NOT NULL CHECK (city IN ('bangalore', 'mumbai', 'hyderabad', 'chennai', 'pune', 'delhi', 'gurgaon')),
  description TEXT NOT NULL,
  duty_timings VARCHAR(20) NOT NULL CHECK (duty_timings IN ('24hrs_live_in', '12hrs_pg')),
  language VARCHAR(50) NOT NULL CHECK (language IN ('hindi', 'english', 'kannada', 'tamil', 'telugu', 'malayalam', 'bengali', 'gujarati', 'marathi')),
  gender_needed VARCHAR(10) NOT NULL CHECK (gender_needed IN ('male', 'female')),
  religion VARCHAR(20) NOT NULL CHECK (religion IN ('hindu', 'muslim', 'christian', 'others')),
  status VARCHAR(10) DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  posted_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at);
