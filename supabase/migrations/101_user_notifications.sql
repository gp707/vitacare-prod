-- Alerts kept under each person's bell icon (caregiver, patient/family, organisation).
--
-- Every push the backend sends (event pushes, daily updates, admin-composed pushes) is also stored
-- here for each recipient account. The app shows the unread ones under the bell; an alert leaves the
-- bell when it is read or 2 days old, whichever comes first (the API never returns older/read rows,
-- and a daily job deletes them).
--
-- Additive: safe to apply before the backend that uses it is deployed.

CREATE TABLE IF NOT EXISTS user_notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  route      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  read_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_user_notifications_user_unread
  ON user_notifications (user_id, created_at DESC) WHERE read_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_user_notifications_created ON user_notifications (created_at);
