-- "Someone couldn't log in" — every FAILED phone login (wrong PIN, no account
-- with that number, a deactivated account, logging in on the wrong app, a bad
-- or locked OTP) is recorded so the admin Insights screen can show who is
-- stuck and call them. Successful logins already have their own audit row.
--
-- The attempted PIN/OTP is NEVER stored — only that an attempt failed and why.
-- phone is stored as typed (it is the only handle for a person who has no
-- account at all, e.g. someone mistyping their number or who never
-- registered); user_id is set when the number belongs to an account.
-- ON DELETE CASCADE: when an account is deleted, its failed-attempt trail goes
-- with it. Rows are purged after 30 days (InsightsService) — these are
-- operational follow-up data, and unknown-number rows are personal data of
-- people who never became users.
--
-- Deliberately NOT recorded: the first leg of the unified login's
-- patient/organisation -> caregiver fallback. JustHeal's single login screen
-- tries the patient/organisation bucket first and falls back to the caregiver
-- one on "no account", so a caregiver's normal login always produces one
-- bucket miss; that is not a failure (see AuthService.recordMissingAccount).

CREATE TABLE IF NOT EXISTS login_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone VARCHAR(20) NOT NULL,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  user_role VARCHAR(20),
  app VARCHAR(10) NOT NULL CHECK (app IN ('nursejobs', 'nursenow')),
  method VARCHAR(10) NOT NULL CHECK (method IN ('code', 'otp')),
  reason VARCHAR(30) NOT NULL CHECK (reason IN (
    'wrong_pin', 'unknown_account', 'wrong_app', 'account_deactivated',
    'otp_invalid', 'otp_wrong', 'otp_locked'
  )),
  ip_address VARCHAR(45),
  user_agent TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_created_at ON login_attempts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_login_attempts_phone_created ON login_attempts(phone, created_at DESC);
