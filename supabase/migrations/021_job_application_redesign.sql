-- ============================================
-- Job/Application flow redesign: jobs are now built around the care
-- receiver's needs (mobility, communication, feeding, medical assistance)
-- instead of a single "work type" category. Caregivers apply/reject
-- ("ask for more details" removed); admin accepts one applicant (closes
-- the job, moves the caregiver to `assigned`) or, later, rejects that
-- acceptance (reopens the job, moves the caregiver back to `available`).
--
-- Work Type, Service Mode, and Salary Ranges are fully removed — dropped
-- from job postings (the only remaining consumer after the caregiver-side
-- admin-assignment removal in migration 020) with nothing replacing them
-- structurally; the new care-needs fields describe the job instead.
--
-- Existing `jobs`(1 row)/`job_responses`(2 rows) data is this session's
-- own earlier test data (confirmed with the user before running this) and
-- is dropped along with the old tables — the new `jobs` shape requires a
-- NOT NULL `care_receiver_id` that old rows have no way to backfill.
-- ============================================

DROP TABLE IF EXISTS job_responses;
DROP TABLE IF EXISTS jobs;

-- ============================================
-- CARE RECEIVERS TABLE
-- ============================================
CREATE TABLE care_receivers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mobility VARCHAR(30) NOT NULL CHECK (mobility IN (
    'walks_independently', 'walks_with_assistance', 'uses_walker', 'uses_wheelchair', 'bedridden'
  )),
  communication VARCHAR(30) NOT NULL CHECK (communication IN (
    'verbal', 'difficulty_communicating', 'sign_language', 'other_non_verbal'
  )),
  feeding_type VARCHAR(30) NOT NULL CHECK (feeding_type IN (
    'oral_independent', 'oral_needs_assistance', 'tube_feeding', 'oral_and_tube'
  )),
  tube_feeding_needs_assistance BOOLEAN,
  medical_assistance JSONB NOT NULL DEFAULT '[]',
  has_medical_condition BOOLEAN NOT NULL DEFAULT false,
  medical_conditions JSONB NOT NULL DEFAULT '[]',
  medical_info TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- JOBS TABLE (redesigned)
-- ============================================
CREATE TABLE jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  care_receiver_id UUID NOT NULL REFERENCES care_receivers(id),
  city VARCHAR(30) NOT NULL CHECK (city IN (
    'bangalore', 'mumbai', 'hyderabad', 'chennai', 'pune', 'delhi', 'gurgaon'
  )),
  area TEXT,
  description TEXT NOT NULL,
  duty_type VARCHAR(20) NOT NULL CHECK (duty_type IN ('day_duty', 'night_duty', 'live_in', 'other')),
  start_time TIME,
  end_time TIME,
  start_date DATE,
  language VARCHAR(50) NOT NULL CHECK (language IN (
    'hindi', 'english', 'kannada', 'tamil', 'telugu', 'malayalam', 'bengali', 'gujarati', 'marathi'
  )),
  preferred_gender VARCHAR(10) CHECK (preferred_gender IN ('male', 'female')),
  preferred_religion VARCHAR(20) CHECK (preferred_religion IN ('hindu', 'muslim', 'christian', 'others')),
  status VARCHAR(10) DEFAULT 'active' CHECK (status IN ('active', 'closed')),
  posted_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at);
CREATE INDEX idx_jobs_care_receiver ON jobs(care_receiver_id);

-- ============================================
-- JOB APPLICATIONS TABLE (renamed/redesigned from job_responses)
-- ============================================
CREATE TABLE job_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL CHECK (status IN ('applied', 'rejected', 'accepted')),
  decided_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(job_id, profile_id)
);

CREATE INDEX idx_job_applications_job ON job_applications(job_id);
CREATE INDEX idx_job_applications_profile ON job_applications(profile_id);

-- New audit action for the admin accept/reject-application decision.
ALTER TABLE audit_logs DROP CONSTRAINT IF EXISTS audit_logs_action_check;
ALTER TABLE audit_logs ADD CONSTRAINT audit_logs_action_check
  CHECK (action IN (
    'registration', 'login', 'call_verified', 'advanced_details_submitted',
    'profile_updated', 'status_changed', 'code_changed',
    'admin_edit_profile', 'admin_note_added', 'admin_created', 'admin_deactivated',
    'phone_changed', 'edits_acknowledged', 'job_posted', 'job_closed', 'job_response',
    'job_application_decided',
    'admin_document_uploaded', 'admin_role_changed', 'admin_activated', 'job_reminder_sent'
  ));
