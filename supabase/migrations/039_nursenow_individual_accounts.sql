-- NurseNow Phase 1: Individual (patient/family) accounts. Organisation is
-- not added yet — that's a later phase's migration.
ALTER TABLE users DROP CONSTRAINT users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
  CHECK (role IN ('super_admin', 'admin', 'caregiver', 'individual'));

-- Mirrors caregiver_profiles' role-specific-data pattern. No verification
-- workflow like caregivers — just the two admin block levers. Full BLOCKED
-- (can't log in at all) reuses the existing users.is_active flag and
-- AUTH_004 ("Account is deactivated") — already wired into loginCode/
-- loginEmail, so no separate column is needed for that state.
CREATE TABLE individual_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  is_job_posting_blocked BOOLEAN NOT NULL DEFAULT false,
  block_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- An individual-posted job is created without frequency_of_care (admin
-- sets it during approval) — the column must become nullable.
-- salary_amount is already nullable (see 026), no change needed there.
ALTER TABLE jobs ALTER COLUMN frequency_of_care DROP NOT NULL;

-- New pending-review status: an individual's posting sits here until an
-- admin approves (-> active, sets frequency_of_care/salary_amount) or
-- rejects (-> closed) it. Admin's own postings skip this entirely (created
-- straight into 'active', same as today). The column was VARCHAR(10) —
-- long enough for 'active'/'closed' but not 'pending_review' (15 chars) —
-- so it needs widening too.
ALTER TABLE jobs ALTER COLUMN status TYPE VARCHAR(20);
ALTER TABLE jobs DROP CONSTRAINT jobs_status_check;
ALTER TABLE jobs ADD CONSTRAINT jobs_status_check
  CHECK (status IN ('pending_review', 'active', 'closed'));

-- Only meaningful when an admin rejects a pending_review job — null
-- otherwise, including for a normal close.
ALTER TABLE jobs ADD COLUMN rejection_reason TEXT;
