-- Admin-only personal/internal notes for organisation (hospital/rehab/
-- clinic) accounts — same shape as job_admin_notes/individual_admin_notes
-- (see 075_admin_code_reset_and_job_individual_notes.sql), completing the
-- same capability for the one remaining account type that didn't have it.

CREATE TABLE organisation_admin_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  admin_id UUID NOT NULL REFERENCES users(id),
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id)
);
