-- ============================================
-- JOB RESPONSES TABLE (caregiver responses to jobs)
-- ============================================
CREATE TABLE job_responses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  response VARCHAR(20) NOT NULL CHECK (response IN ('accepted', 'rejected', 'more_details')),
  message TEXT,                           -- Question text when response is 'more_details'
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(job_id, profile_id)
);

CREATE INDEX idx_job_responses_job ON job_responses(job_id);
CREATE INDEX idx_job_responses_profile ON job_responses(profile_id);
