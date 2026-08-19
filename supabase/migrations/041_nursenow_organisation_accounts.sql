-- NurseNow Organisation (hospital/rehab/clinic) accounts — the deferred
-- second half of NurseNow (see "NurseNow" in CLAUDE.md). Unlike Individual,
-- which reuses jobs/care_receivers/job_applications, Organisation gets
-- brand-new dedicated tables: a fundamentally different posting shape (no
-- care_receiver, a "type of nurse" enum instead of a qualification enum,
-- accommodation/food/special-skills fields, no city/duty-type section —
-- city/area are inherited from the org's own registered location) and
-- many simultaneous postings per org (no one-live-requirement limit).

ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
  CHECK (role IN ('super_admin', 'admin', 'caregiver', 'individual', 'organisation'));

-- Role-specific data for an organisation account. Mirrors
-- individual_profiles' shape (no verification pipeline, just the two
-- admin block levers) plus the registration-collected org identity/location
-- fields. city/area here are the org's own registered location, reused as
-- every one of its requirements' location (no per-requirement city/area).
-- city is validated at the DTO layer against the existing 7-city list plus
-- 'others' — a separate org-scoped list, NOT an extension of the shared
-- City enum (which stays caregiver/job-scoped).
CREATE TABLE organisation_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  organisation_name VARCHAR(200) NOT NULL,
  contact_person_name VARCHAR(100) NOT NULL,
  organisation_type VARCHAR(20) NOT NULL CHECK (organisation_type IN ('hospital', 'rehab', 'clinic')),
  city VARCHAR(30) NOT NULL,
  area TEXT NOT NULL,
  is_job_posting_blocked BOOLEAN NOT NULL DEFAULT false,
  block_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Full block (can't log in at all) reuses users.is_active + AUTH_004,
-- exactly like individual_profiles — no separate column needed.

-- An organisation's posted requirement — deliberately NOT a jobs row (see
-- header). type_of_nurse validated at the DTO layer against a fixed
-- 12-value list (packages/shared-constants TypeOfNurse), not a DB CHECK,
-- so the list can be adjusted without a migration. frequency_of_care /
-- salary_amount / start_date are admin-set on approval, same
-- null-until-approved pattern as jobs.frequency_of_care for an individual's
-- posting; start_date is only ever set when frequency_of_care = 'daily'
-- (enforced at the DTO/service layer, not the DB). No care_receiver_id,
-- no city/area/duty_type — an org requirement's location is implicitly its
-- own organisation_profiles.city/area.
CREATE TABLE organisation_requirements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requirement_number SERIAL UNIQUE,
  posted_by UUID NOT NULL REFERENCES users(id),
  type_of_nurse VARCHAR(40) NOT NULL,
  frequency_of_care VARCHAR(10) CHECK (frequency_of_care IN ('daily', 'monthly')),
  salary_amount INTEGER CHECK (salary_amount > 0),
  start_date DATE,
  accommodation_provided BOOLEAN NOT NULL,
  food_provided BOOLEAN NOT NULL,
  special_skills TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending_review'
    CHECK (status IN ('pending_review', 'active', 'closed')),
  rejection_reason TEXT,
  posted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_organisation_requirements_status ON organisation_requirements(status);
CREATE INDEX idx_organisation_requirements_posted_by ON organisation_requirements(posted_by);

-- Caregiver applications to an organisation requirement — a separate table
-- from job_applications (same reasoning as the requirements table itself),
-- but shaped identically, including 'completed' status and decline_reason
-- from day one (job_applications only grew those in migrations 035/040).
CREATE TABLE organisation_requirement_applications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requirement_id UUID NOT NULL REFERENCES organisation_requirements(id) ON DELETE CASCADE,
  profile_id UUID NOT NULL REFERENCES caregiver_profiles(id) ON DELETE CASCADE,
  status VARCHAR(20) NOT NULL CHECK (status IN ('applied', 'rejected', 'accepted', 'completed')),
  decided_by UUID REFERENCES users(id),
  applied_at TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  decline_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(requirement_id, profile_id)
);

CREATE INDEX idx_org_requirement_applications_requirement ON organisation_requirement_applications(requirement_id);
CREATE INDEX idx_org_requirement_applications_profile ON organisation_requirement_applications(profile_id);
